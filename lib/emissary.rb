require 'rubygems'

require 'uuid'
require 'digest/md5'
require 'thread'
require 'yaml'
require 'fastthread' rescue nil

require 'emissary/errors'

module Emissary

  # :stopdoc:
  LIBPATH = ::File.expand_path(::File.dirname(__FILE__)) + ::File::SEPARATOR
  PATH = ::File.dirname(LIBPATH) + ::File::SEPARATOR
  VERSION = ::YAML.load(File.read(File.join(PATH, 'VERSION.yml'))).values.join '.'

  EXTERNALS_BASE      = ::File.join(::File::SEPARATOR, 'opt')
  EXTERNAL_IDENTITIES = ::File.join(EXTERNALS_BASE, 'emissary', 'identities')
  EXTERNAL_AGENTS     = ::File.join(EXTERNALS_BASE, 'emissary', 'agents')
  EXTERNAL_OPERATORS  = ::File.join(EXTERNALS_BASE, 'emissary', 'operators')

  DEFAULT_EXCHANGE        = :direct
  DAEMON_RECHECK_INTERVAL = 10
  IP_CHECK_DOMAIN         = 'checkip.dyndns.org'
  IP_CHECK_URL            = "http://#{IP_CHECK_DOMAIN}"
  # :startdoc:

  $:.unshift File.join(LIBPATH, 'lib')
  
  # autoload core object extensions
  Dir[File.join(Emissary::LIBPATH, 'emissary', 'core_ext', '*.rb')].each do |core_extension|
    require core_extension
  end

  @@pid = nil
  def self.PID
    @@pid
  end
  
  # Returns the version string for the library.
  #
  def self.version
    VERSION
  end

  # Returns the library path for the module. If any arguments are given,
  # they will be joined to the end of the libray path using
  # <tt>File.join</tt>.
  #
  def self.libpath( *args )
    args.empty? ? LIBPATH : ::File.join(LIBPATH, args.flatten)
  end

  # Returns the path for the module. If any arguments are given,
  # they will be joined to the end of the path using
  # <tt>File.join</tt>.
  #
  def self.path( *args )
    args.empty? ? PATH : ::File.join(PATH, args.flatten)
  end

  def self.klass_from_handler(klass = nil, handler = nil, *args)
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
      raise ArgumentError, "klass must be a valid class constant for #{self.name}#klass_from_handler"
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

  def self.klass_loaded?(class_name)
    begin
      !!klass_const(class_name)
    rescue NameError
      false
    end
  end

  def self.klass_const(class_name, autoload = false)
    return class_name if class_name.is_a? Class or class_name.is_a? Module

    klass = Object
    
    class_name.split('::').each do |c|
      begin
        klass = klass.const_get(c.to_sym)
      rescue NameError =>e 
        if autoload
          require_klass( (klass == Object ? c : "#{klass.to_s}::#{c}") )
          redo
        end
      end
    end
    
    klass.to_s == class_name ? klass : nil
  end
  
  def self.load_klass(class_name)
    load File.join(LIBPATH, *class_name.downcase.split(/::/)) + '.rb'
  end
  
  def self.require_klass(class_name)
    require File.join(*class_name.downcase.split(/::/))
  end

  def self.logger
    require 'emissary/logger'
    Emissary::Logger.instance
  end
  
  def self.generate_uuid
    UUID.generate
  end
  
  def self.identity
    require 'emissary/identity'
    @@identity ||= Emissary::Identity.new
  end
  
  # Sets up a line of communication
  #
  def self.call handler, config, *args
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
  def self.dispatch message, config, *args
    raise ArgumentError, "message is not an Emissary::Message" unless message.is_a? Emissary::Message
        
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
      e = Emissary::Error.new(e)
      Emissary.logger.error "DispatchError: #{e.message}"
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
end # module Emissary
