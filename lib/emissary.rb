#   Copyright 2010 The New York Times
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
#
require 'rubygems'
require 'uuid'
require 'digest/md5'
require 'yaml'
require 'pathname'

begin
  require 'thread'
  require 'fastthread'
rescue LoadError
end

module Emissary
  # :stopdoc:
  LIBPATH = Pathname.new(__FILE__).dirname.realpath 
  PATH    = LIBPATH.dirname
  VERSION = ::YAML.load(File.read(PATH + 'VERSION.yml')).values.join '.'

  EXTERNALS_BASE      = Pathname.new('/opt/emissary')
  EXTERNAL_IDENTITIES = EXTERNALS_BASE + 'identities'
  EXTERNAL_AGENTS     = EXTERNALS_BASE + 'agents'
  EXTERNAL_OPERATORS  = EXTERNALS_BASE + 'operators'

  DEFAULT_EXCHANGE        = :direct
  DAEMON_RECHECK_INTERVAL = 10
  IP_CHECK_DOMAIN         = 'checkip.dyndns.org'
  IP_CHECK_URL            = "http://#{IP_CHECK_DOMAIN}"
  # :startdoc:

  class << self 
    @@pid = nil
    def PID
      @@pid
    end
    
    # Returns the version string for the library.
    #
    def version
      VERSION
    end
  
    # Returns the library path for the module. If any arguments are given,
    # they will be joined to the end of the libray path using
    # <tt>File.join</tt>.
    #
    def libpath( *args )
      LIBPATH.join(args.flatten)
    end
  
    # Returns the path for the module. If any arguments are given,
    # they will be joined to the end of the path using
    # <tt>File.join</tt>.
    #
    def path( *args )
      args.empty? ? PATH : File.join(PATH, args.flatten)
    end

    def sublib_path( *args )
      args.empty? ? PATH : File.join(LIBPATH, 'emissary', args.flatten)
    end
    
    def klass_from_handler(klass = nil, handler = nil, *args)
      klass = if handler and handler.is_a? Class and not handler.nil?
        raise ArgumentError, "must provide module or subclass of #{klass.name}" unless klass >= handler
        handler
      elsif handler.is_a? Module
        resource_name = "RESOURCE_#{handler.to_s.upcase.split('::').pop}"
        begin
          klass.const_get(resource_name)
        rescue NameError
          klass.const_set(resource_name, Class.new(klass) { include handler } )
        end
      elsif klass.nil?
        raise ArgumentError, "klass must be a valid class constant for #{name}#klass_from_handler"
      elsif handler.nil?
        raise ArgumentError, "handler must be a valid class or module"
      else
        klass
      end
  
      arity = klass.instance_method(:initialize).arity
      expected = arity >= 0 ? arity : -(arity + 1)
      if (arity >= 0 and args.size != expected) or (arity < 0 and args.size < expected)
        raise ArgumentError, "wrong number of arguments for #{klass}#initialize (#{args.size} for #{expected})"
      end
  
      klass
    end
  
    def klass_loaded?(class_name)
      begin
        !!klass_const(class_name)
      rescue NameError
        false
      end
    end
  
    def klass_const(class_name, autoload = false)
      return class_name if class_name.is_a? Class or class_name.is_a? Module
  
      klass = Object
      
      class_name.split('::').each do |c|
        begin
          klass = klass.const_get(c.to_sym)
        rescue NameError => e 
          if autoload
            require_klass( (klass == Object ? c : "#{klass.to_s}::#{c}") )
            redo
          end
        end
      end
      
      klass.to_s == class_name ? klass : nil
    end
    
    def load_klass(class_name)
      load libpath(*class_name.downcase.split(/::/)) + '.rb'
    end
    
    def require_klass(class_name)
      require libpath(*class_name.downcase.split(/::/))
    end
  
    def logger
      Emissary::Logger.instance
    end
    
    def generate_uuid
      UUID.generate
    end
    
    def identity
      @@identity ||= Emissary::Identity.instance
    end
    
    # Sets up a line of communication
    #
    def call handler, config, *args
      unless handler.is_a? Class or handler.is_a? Module
        klass_name = 'Emissary::Operator::' + handler.to_s.upcase
        begin
          require_klass klass_name
        rescue LoadError => e
          begin
            require_klass Emissary::EXTERNAL_OPERATORS + '::' + handler.to_s.upcase
          #rescue LoadError
            # raise the original exception if we still haven't found the file
          #  raise e
          end
        end
        handler = klass_const klass_name
      end
      
      klass = klass_from_handler(Operator, handler, config)
  
      operator = klass.new(config, *args)
      operator.validate_config!
      block_given? and yield operator
      operator
    end
  
    # Dispatches a message to the agent specified by the message
    #
    def dispatch message, config, *args
      unless message.is_a? Emissary::Message
        raise ArgumentError, "message is not an Emissary::Message" 
      end
      
      begin
        agent_type = 'Emissary::Agent::' + message.agent.to_s.capitalize
        begin
          require_klass agent_type 
        rescue LoadError => e
          begin
            require_klass Emissary::EXTERNAL_AGENTS + '::' + message.agent.to_s.capitalize
          rescue LoadError
            # raise the original exception if we still haven't found the file
            raise e
          end
        end
      rescue Exception => e
        Emissary.logger.error "Dispatcher Error: #{e.class.name}: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
        message = message.error(e)
        agent_type = 'Emissary::Agent::Error'
      end
  
      handler = klass_const agent_type, true
      
      klass = klass_from_handler(Agent, handler, message, config, *args)
  
      Emissary.logger.debug " [--] Dispatching message to: #{agent_type}"
      agent = klass.new(message, config, *args)
      block_given? and yield agent
      agent
    end
  end

  # autoload core object extensions
  Dir[sublib_path('core_ext', '*.rb')].each do |core_extension|
    require core_extension
  end
end # module Emissary

$:.unshift Emissary::LIBPATH

[ :errors, :logger, :operator, :agent, :identity, :message, :config, :gem_helper ].each do |sublib|
  require Emissary.sublib_path sublib.to_s
end
