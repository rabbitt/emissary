require 'emissary'

module Emissary
  class Error < StandardError

    attr_reader :origin

    def self.new(*args) #:nodoc:
      allocate.instance_eval do
        alias :original_instance_of? :instance_of?
        alias :original_kind_of? :kind_of?
  
        def instance_of? klass
          self.original_instance_of? klass or origin.instance_of? klass
        end
    
        def kind_of? klass
          self.original_kind_of? klass or origin.kind_of? klass
        end

        # Call a superclass's #initialize if it has one
        initialize(args[1] || '')

        self
      end
    end

    def initialize(origin = Exception, message = '')
      
      if origin.kind_of? Exception
        @origin = origin
      else
        if origin.kind_of? Class
          @origin = origin.new
        else
          @origin = Exception.new 
        end
      end

      super message
    end

    def message(include_trace = true)
      _class   = origin.class
      _message = "#{_class}: " << (origin.kind_of?(Emissary::Error) ? origin.message(false) : origin.message)
      _trace   = ((include_trace ? "\n\t" << trace.join("\n\t") : '')  rescue '')
      "#{_message} #{_trace}"
    end
    
    def trace
      (self.backtrace || []) + ((origin.respond_to?(:trace) ? origin.trace : origin.backtrace) || [])
    end
  end
end

if __FILE__ == $0
  begin
    begin
      begin
        raise Emissary::Error.new(ArgumentError, "testing")
      rescue Emissary::Error => e
        puts "1: " << e.message
        raise Emissary::TrackingError.new(e)
      end
    rescue Emissary::Error => e
      puts "2: " << e.message
      raise Emissary::NetworkEncapsulatedError.new(e)
    end
  rescue Emissary::Error => e
    puts "3: " << e.message
  end
  
  [ Exception, ArgumentError, Emissary::Error, Emissary::TrackingError, Emissary::NetworkEncapsulatedError].each do |k|
    puts "e.kind_of?(#{k.name}): #{e.kind_of? k}"
  end
end
