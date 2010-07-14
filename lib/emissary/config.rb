require 'inifile'

require 'emissary'
require 'emissary/errors'

#
# This class represents the INI file and can be used to parse INI files.
# Derived from IniFile gem, found on http://rubyforge.org/projects/inifile/
#
module Emissary
  class ConfigParseError < ::Emissary::Error
    def initialize(message)
      super(Exception, message)
    end
  end
  
  class ConfigValidationError < ::Emissary::Error
    def initialize(message)
      super(Exception, message)
    end
  end

  class ConfigFile < IniFile

    attr_reader :ini
    def initialize( filename, opts = {} )
      @line_number = 0
      @fn = filename
      @comment = opts[:comment] || '#'
      @param = opts[:parameter] || '='
      @debug = !!opts[:debug]
      @ini = Hash.new {|h,k| h[k] = Hash.new}
  
      @rgxp_comment    = /^\s*$|^\s*[#{@comment}]/
      @rgxp_section    = /^\s*\[([^\]]+)\]/
      @rgxp_param      = /^([^#{@param}]+)#{@param}(.*)$/
  
      @rgxp_dict_start = /^([^#{@param}]+)#{@param}\s*\{\s*$/
      @rgxp_dict_stop  = /^\s*\}\s*$/
      @dict_stack      = []
  
      @rgxp_list_start = /^([^#{@param}]+)#{@param}\s*\[\s*$/
      @rgxp_list_line  = /^([^#{@param}]+)#{@param}\s*\[\s*([^\]]+)\]\s*$/
      @rgxp_list_stop  = /^\s*\]\s*$/
      @list_items      = []
      @in_list_name    = nil
      
      super filename, opts
      
      yield self if block_given?
    end
  
    #
    # call-seq:
    #    ini_file[section]
    #
    # Get the hash of parameter/value pairs for the given _section_.
    #
    def []( section )
      return nil if section.nil?
      @ini[section.to_sym]   
    end   
           
    #
    # call-seq:
    #    has_section?( section )
    #
    # Returns +true+ if the named _section_ exists in the INI file.
    #
    def has_section?( section )
      @ini.has_key? section.to_sym
    end
  
    #
    # call-seq:
    #    parse
    #
    # Loops over each line of the file, passing it off to the parse_line method
    #
    def parse
      return unless ::Kernel.test ?f, @fn
      @section_name = nil
      ::File.open(@fn, 'r') do |f|
        while line = f.gets
          @line_number += 1
          parse_line line.chomp
        end
      end
      @section_name = nil
      @line_number  = 0
      return
    end
  
    #
    # call-seq:
    #    set_vall( key, value) => value
    #
    # Sets the value of the given key taking the current stack level into account
    #
    def set_value key, value
      begin
        p = @ini[@section_name]
        @dict_stack.map { |d| p = (p[d]||={}) }
        p[key] = value
      rescue NoMethodError
        raise ConfigParseError, "sectionless parameter declaration encountered at line #{@line_number}"
      end
    end
    
    private
    
    #
    # call-seq:
    #    current_state (param = nil) => state
    #
    # Used for outputing the current parameter hash heirarchy in debug mode
    #
    def current_state param = nil
      state = "@ini[:#{@section_name}]"
      state << @dict_stack.collect { |c| "[:#{c}]" }.join unless @dict_stack.empty?
      state << "[:#{@in_list_name}]" unless @in_list_name.nil?
      state << "[:#{param}]" unless param.nil?
      state
    end
  
    #
    # call-seq:
    #    parse_line(line)
    #
    # Parses the given line
    #
    def parse_line line
      line.gsub!(/\s+#.*$/, '') # strip comments
  
      # replace __FILE__ with the file being parsed
      line.gsub!('__FILE__', File.expand_path(@fn))
      
      # replace __DIR__ with the path of the file being parsed
      line.gsub!('__DIR__', File.dirname(File.expand_path(@fn)))  

      # replace __ID_<METHOD>__ with Emissary.identity.<method>
      [ :name, :instance_id, :server_id, :cluster_id, :account_id ].each do |id_method|
        line.gsub!("__ID_#{id_method.to_s.upcase}__", Emissary.identity.__send__(id_method).to_s)
      end
      
      if not @in_list_name.nil? and line !~ @rgxp_list_stop
        line = line.strip.split(/\s*,\s*/).compact.reject(&:blank?)
        Emissary.logger.debug  "  ---> LIST ITEM #{current_state} << #{line.inspect}" if @debug
        # then we're in the middle of a list item, so add to it
        @list_items = @list_items | line
        return
      end
      
      case line
        # ignore blank lines and comment lines
        when @rgxp_comment: return
    
        # this is a section declaration
        when @rgxp_section
          Emissary.logger.debug  "SECTION: #{line}" if @debug
  
          unless @in_dict_name.nil?
            raise ConfigParseError, "dictionary '#{@in_dict_name}' crosses section '#{$1.strip.downcase}' boundary at line #{@line_number}"
          end
          
          @section_name = $1.strip.downcase.to_sym
          @ini[@section_name] ||= {}
          
        when @rgxp_dict_start
          @dict_stack << $1.strip.downcase.to_sym
          Emissary.logger.debug  "  ---> DICT_BEG: #{@dict_stack.last}" if @debug
          
        when @rgxp_dict_stop
          raise ConfigParseError, "end of dictionary found without beginning at line #{@line_number}" if @dict_stack.empty?
          Emissary.logger.debug  "  ---> DICT_END: #{@dict_stack.last}" if @debug
          @dict_stack.pop 
          return
  
        when @rgxp_list_line
          list_name = $1.strip.downcase.to_sym
          list_items = $2.strip.split(/\s*,\s*/).compact.reject(&:blank?)
          
          unless not @debug
            Emissary.logger.debug "  ---> LIST_BEG: #{list_name}"
            list_items.each do |li|
              Emissary.logger.debug "  ---> LIST_ITEM: #{current_state list_name} << [\"#{li}\"]"
            end
            Emissary.logger.debug "  ---> LIST_END: #{list_name}" 
          end
          
          set_value list_name, list_items
          
        when @rgxp_list_start
          Emissary.logger.debug "  ---> LIST_BEG: #{line}" if @debug
          @in_list_name = $1.strip.downcase.to_sym
  
        when @rgxp_list_stop
          Emissary.logger.debug "  ---> LIST_END: #{@in_list_name} - #{@list_items.inspect}" if @debug
          raise ConfigParseError, "end of list found without beginning at line #{@line_number}" if @in_list_name.nil?
          set_value @in_list_name, @list_items
          
          @in_list_name = nil
          @list_items = []
          
        when @rgxp_param
          val = $2.strip
          val = val[1..-2] if val[0..0] == "'" || val[-1..-1] == '"'
    
          key = $1.strip.downcase.to_sym
          Emissary.logger.debug  "  ---> PARAM: #{current_state key} = #{val}" if @debug
          set_value key, val
  
      else
        raise Exception, "Unable to parse line #{@line_number}: #{line}"
      end
      return true
    end
  end
end
