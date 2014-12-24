class JsxCore
  def initialize(cs_version)
    @error_fd = nil
    @tm_filepath = Pathname.new(ENV["TM_FILEPATH"])
    
    # app
    @target = ""
    @app_path_id = "Adobe InDesign #{cs_version}.app"
    @app_path_ai = "/Applications/Adobe Illustrator #{cs_version == 'CS5.5' ? 'CS5.1' : cs_version}/Adobe Illustrator.app"
    @app_path_ps = "Adobe Photoshop #{cs_version == 'CS5.5' ? 'CS5.1' : cs_version}.app"

    # tempfile
    @tempo_as = Tempfile::new(["",".scpt"])
    @tempo_wr = Tempfile::new(["",".log"])
    @tempo_js = Tempfile::new(["",".jsx"])
  end

  
  def exec
    create_temp_javascript
    create_temp_applescript
    run_osascript
  end
  
  
  def switch_app
    # switch application
    if @target.match 'photoshop'
      @app = @app_path_ps
      @run = "do javascript file (fileName as POSIX file)"
    elsif @target.match 'illustrator'
      @app = @app_path_ai
      @run = "do javascript file (fileName as POSIX file)"
    else
      @app = @app_path_id
      @run = "do script file (fileName as POSIX file) language javascript"
    end
  end


  def create_temp_javascript
    open(@tm_filepath) do |org_js|
      # target app.
      jsx = org_js.read
      @target = (jsx.scan(/^#target\s+.+/).first || "#target indesign").downcase

      # override $.write and $.writeln function, set tempo_wr obj to tempo_js
      open(@tempo_js.path, "w") do |js|
        include_current_path = @tm_filepath.parent.to_s

        jsx_header = <<-JSX_HEAD
var ___ = new File("<%= @tempo_wr.path %>");
___.encoding="UTF8";
___.lineFeed="unix";
___.open("e");
$.write=function(){___.seek(0,2);___.write(arguments[0])};
$.writeln=function(){___.seek(0,2);___.writeln(arguments[0])};

#includepath <%= include_current_path %>

<%= jsx %>
___.close();
JSX_HEAD
        run_jsx = ERB.new(jsx_header).result(binding).gsub("\\","\\\\")

        js.write(run_jsx)
      end
    end
  end


  def create_temp_applescript
    
    switch_app
    
    # generate applescript
    # run applescript by osascript
    as_template = <<-APPLESCRIPT
on run argv
  set fileName to item 1 of argv
  tell application \"<%= @app %>\"
    with timeout of (1 * 60 * 60) seconds
      <%= @run %>
    end timeout
  end tell
  return true
end run
APPLESCRIPT
    run_scpt = ERB.new(as_template).result(binding)

    # write script to applescript file
    open(@tempo_as.path, "w") do |as|
      as.write run_scpt
    end
  end


  def run_osascript
    TextMate::Executor.run(ENV["TM_OSASCRIPT"] || "osascript", @tempo_as.path, @tempo_js.path ) do |str, type|
      @error_fd ||= IO.for_fd(ENV["TM_ERROR_FD"].to_i)
      case type
      when :err
        # # error
        # if str =~ /^([^\:]+):(\d+):(\d+): (.*?): (.*) \((-?\d+)\)$/ then
        #   filepath, start,  stop, err, msg, status = $1, $2.to_i, $3.to_i, $4, $5, $6
        #   err = err.gsub(/\b\w(?=\w{3,})/) { |m| m.upcase }
        #         
        #   @error_fd << "<div id=\"exception_report\" class=\"framed\">\n"
        #   @error_fd << "<p id=\"exception\"><strong>#{htmlize err}</strong>: #{htmlize msg}</p>\n"
        #             
        #   @error_fd << "<p>Error #{status}.</p>\n"
        #   @error_fd << "</div>\n"
        #   @error_fd.flush
        #   ""
        # else
        #   "<span class=\"err\" style=\"color:red;\">#{htmlize(str)}</span><br/>"
        # end
      when :out
        # read log writen by $.write(), $.writeln() in tempo_js
        @tempo_wr.open
        str = "" # clear "true"
        str << @tempo_wr.read
        @tempo_wr.close!

        htmlize(str)
      end
    end
  end
  
end


