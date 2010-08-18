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
require 'emissary/servolux'
require 'emissary/server'
require 'daemons'

module Emissary
  
  # Some of the ServerController/Daemon stuff has been borrowed
  # from Servolux::Daemon and Servolux::Server, so:
  # Thanks to Tim Pease for those parts that are gleaned from Servolux
  module ServerController
    
    SIGNALS = %w[HUP INT TERM USR1 USR2 EXIT] & Signal.list.keys
    SIGNALS.each {|sig| sig.freeze}.freeze

    DEFAULT_PID_FILE_MODE = 0640
    
    attr_accessor :pid_file_mode
    attr_writer :pid_file

    # Returns +true+ if the daemon process is currently running. Returns
    # +false+ if this is not the case. The status of the process is determined
    # by sending a signal to the process identified by the +pid_file+.
    #
    # @return [Boolean]
    #
    def alive?
      pid = retrieve_pid
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH, Errno::ENOENT
      false
    rescue Errno::EACCES => err
      logger.error "You do not have access to the PID file at " \
                   "#{pid_file.inspect}: #{err.message}"
      false
    end
  
    def retrieve_pid
      Integer(File.read(pid_file).strip)
    rescue TypeError
      raise Error, "A PID file was not specified."
    rescue ArgumentError
      raise Error, "#{pid_file.inspect} does not contain a valid PID."
    end

    # Send a signal to the daemon process identified by the PID file. The
    # default signal to send is 'INT' (2). The signal can be given either as a
    # string or a signal number.
    #
    # @param [String, Integer] signal The kill signal to send to the daemon
    # process
    # @return [Daemon] self
    #
    def kill( signal = 'INT' )
      signal = Signal.list.invert[signal] if signal.is_a?(Integer)
      pid = retrieve_pid
      logger.info "Killing PID #{pid} with #{signal}"
      Process.kill(signal, pid)
      self
    rescue Errno::EINVAL
      logger.error "Failed to kill PID #{pid} with #{signal}: " \
                   "'#{signal}' is an invalid or unsupported signal number."
    rescue Errno::EPERM
      logger.error "Failed to kill PID #{pid} with #{signal}: " \
                   "Insufficient permissions."
    rescue Errno::ESRCH
      logger.error "Failed to kill PID #{pid} with #{signal}: " \
                   "Process is deceased or zombie."
    rescue Errno::EACCES => err
      logger.error err.message
    rescue Errno::ENOENT => err
      logger.error "Could not find a PID file at #{pid_file.inspect}. " \
                   "Most likely the process is no longer running."
    rescue Exception => err
      unless err.is_a?(SystemExit)
        logger.error "Failed to kill PID #{pid} with #{signal}: #{err.message}"
      end
    end
  
    def pid
      alive? ? retrieve_pid : nil
    end

    def pid_file
      @pid_file ||= File.join(config[:general][:pid_dir], (config[:general][:pid_file] || 'emissary.pid'))
    end

    def pid_dir
      @pid_dir ||= File.join(config[:general][:pid_dir])
    end

    def create_pid_file
      logger.debug "Server #{name.inspect} creating pid file #{pid_file.inspect}"
      File.open(pid_file, 'w', pid_file_mode) {|fd| fd.write(Process.pid.to_s)}
    end
  
    def delete_pid_file
      if test(?f, pid_file)
        pid = Integer(File.read(pid_file).strip)
        return unless pid == Process.pid
  
        logger.debug "Server #{name.inspect} removing pid file #{pid_file.inspect}"
        File.delete(pid_file)
      end
    end
  
    def trap_signals
      SIGNALS.each do |sig|
        m = sig.downcase.to_sym
        Signal.trap(sig) { self.send(m) rescue nil } if self.respond_to? m
      end
    end
  end
  
  class Daemon
    include Emissary::ServerController

    SHUTDOWN_RETRY = 1
    MAX_RESTARTS   = 10
    REQUIRED_AGENTS = [ :emissary, :ping, :error ]
    
    attr_accessor :logger, :state, :name, :config, :config_file
    attr_reader :operators

    def initialize(name, opts = {})
    
      @operators = {}
      @name = name
      @mutex = Mutex.new
      @shutdown = nil
      
      self.class.const_set('STARTUP_OPTS', opts.clone_deep)
      @config_file = File.expand_path(opts.delete(:config_file) || '/etc/emissary/config.ini')
      @config = Daemon.get_config(config_file, STARTUP_OPTS)
      
      self.class.const_set('CONFIG_FILE', @config_file)
      
      @logger = Emissary::Logger.instance
      @logger.level = @config[:general][:log_level]

      @pid_file = config[:general][:pid_file]
      @pid_file_mode = config[:general][:pid_file_mode] || DEFAULT_PID_FILE_MODE
    
      ary = %w[name config_file].map { |var|
        self.send(var.to_sym).nil? ? var : nil
      }.compact
      raise Error, "These variables are required: #{ary.join(', ')}." unless ary.empty?
    end
    
    def self.get_config(config_file, opts = {})
      config = Daemon.validate_config!(Emissary::ConfigFile.new(config_file))

      config[:general][:daemonize] = opts.delete(:daemonize) || false
      
      config[:general][:agents] ||= 'all'
      config[:general][:agents] = if config[:general][:agents].instance_of? String
        config[:general][:agents].split(/\s*,\s*/)
      else
        config[:general][:agents].to_a
      end
      
      config[:general][:log_level] = opts.delete(:log_level) || config[:general][:log_level] || 'NOTICE'

      unless (log_level = config[:general][:log_level]).kind_of? Fixnum
        case log_level
          when /^(LOG_){0,1}([A-Z]+)$/i
            log_level = Emissary::Logger::CONSTANT_NAME_MAP[$2]
          when Symbol
            log_level = Emissary::Logger::CONSTANT_NAME_MAP[log_level]
          when /[0-9]+/
            log_level = log_level.to_i
        end
        config[:general][:log_level] = log_level
      end
      
      config[:general][:pid_dir]  = opts.delete(:pid_dir)  || '/var/run'
      
      # set up defaults
      config[:agents] ||= {}
      config[:agents][:emissary] ||= {}
      config[:agents][:emissary][:config_file] = File.expand_path(config_file)
      config[:agents][:emissary][:config_path] = File.dirname(File.expand_path(config_file))

      
      config[:general][:operators].each do |operator|
        config[operator.to_sym].each do |name,data|
            # setup the enabled and disabled agents on a per operator basis
            agents = data[:agents].blank? ? config[:general][:agents] : if data[:agents].kind_of?(Array)
              data[:agents]
            else
              data[:agents].split(/\s*,\s*/)
            end
            
            disable = agents.select { |v| v =~ /^-/ }.inject([]) { |a,v| a << v.gsub(/^-/,'').to_sym }
            disable.include?(:all) && disable.delete_if { |v| v != :all }
            
            enable = agents.select { |v| v !~ /^-/ }.inject([]) { |a,v| a << v.to_sym; a }
            enable.include?(:all) && enable.delete_if { |v| v != :all }
            
            # don't let the user disable REQUIRED AGENTS
            disable -= REQUIRED_AGENTS
            
            enable = ( enable.include?(:all) ? [ :all ] : enable | REQUIRED_AGENTS )
            
                                                if not (conflicts = (enable - (enable - disable))).empty?
                                                        raise "Conflicting enabled/disabled agents: [#{conflicts.join(', ')}] - you can not both specifically enable and disable an agent!"
                                                end
            
            # now copy over the agent specific settings and
            # append __enabled__ and __disabled__ list
            data[:agents] = config[:agents].clone
            data[:agents][:__enabled__] = enable
            data[:agents][:__disabled__] = disable
        end
      end

      config
    end

    def self.validate_config!(config)
      unless config[:general]
        raise ::Emissary::ConfigValidationError.new(Exception, "Missing 'general' section in configuration file")
      end
      
      unless config[:general][:operators]
        logger.debug config[:general].inspect
        raise ::Emissary::ConfigValidationError.new(Exception, "[general][operators] not set")
      end
      
      unless config[:general][:operators].kind_of? Array
        raise ::Emissary::ConfigValidationError.new(Exception, "[general][operators] not a list")
      end
      
      config[:general][:operators].each do |operator|
        operator = operator.to_sym
        unless config[operator]
          raise ::Emissary::ConfigValidationError.new(Exception, "Missing Operator Section '#{operator}'")
        end
        
        unless config[operator].kind_of? Hash
          raise ::Emissary::ConfigValidationError.new(Exception, "Operator Section '#{operator}' not a dictionary of operators")
        end
      end

      config
    end
    
    def become_daemon
      # switch to syslog mode for logging
      @logger.mode  = Emissary::Logger::LOG_SYSLOG
      Daemonize::daemonize(nil, name)
      create_pid_file
    end
    
    def can_startup? operator
      result = true
      result &= (!operator[:daemon] || !operator[:daemon].alive?)
      result &= operator[:start_count] < MAX_RESTARTS
      result &= (not @shutting_down)
      result
    end
    
    def call_operators
      config[:general][:operators].each do |operator|
        opsym = operator.to_sym
        config[opsym].each do |name,data|
          op = Emissary.call operator, data.merge({:signature => name, :parent_pid => $$})
          @operators[op.signature] = { :operator => op, :start_count => 0 }
        end
      end
    end

    def reconfig
      Emissary.logger.warn "Reloading configuration."
      begin
        new_config = Daemon.get_config(config_file, STARTUP_OPTS)
      rescue Exception => e
        Emissary.logger.error "Unable to reload configuration due to error:\n#{e.message}\n\t#{e.backtrace.join("\n\t")}"
      else
        @config = new_config
      end
      self.restart
    end
    
    def restart
      shutdown false
      startup
    end
    
    def startup
      return if alive?
      
      begin
        become_daemon if config[:general][:daemonize]
        trap_signals
        call_operators
        start_run_loop
      rescue StandardError => e
        Emissary.logger.error "Error Starting up: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
      ensure
        delete_pid_file
      end
    end

    def shutdown do_exit = true
      Emissary.logger.info "Shutdown Requested - Stopping operators"

      @operators.each_key do |name|
        operator = do_exit ? @operators.delete(name) : @operators[name]
        
        Emissary.logger.notice "Shutting down operator '#{name}' - current status: #{operator[:daemon].alive? ? 'running' : 'stopped'}"
        while operator[:daemon].alive? 
          Emissary.logger.debug "[SHUTDOWN] Hanging Up on Operator call '#{name}' (process: #{operator[:daemon_pid]})"
          # should have shutdown above but, let's be sure here
          operator[:daemon].shutdown if operator[:daemon].alive?
        end

        # Our shutdowns don't count toward restart limit for operators
        # We're only protecting against multiple failed starts with it.
        operator[:start_count] -= 1 unless operator[:start_count] <= 0
      end
  
      if do_exit
        Emissary.logger.info "Shutdown Complete - Exiting..."
        exit!(0)
      end
    end

    def start_run_loop
      while not @shutting_down do
        @operators.each do |name,operator|
          if operators[:start_count].to_i > MAX_RESTARTS
            ::Emissary.logger.warning "Start Count > MAX_RESTARTS for operator '#{name}' - removing from list of operators..."
            @operators.delete(name) 
            next
          end
          
          if can_startup? operator
            Emissary.logger.notice "Starting up Operator: #{name}"
            
            server_data = {
                :operator => @operators[name][:operator],
                :pid_file => File.join(pid_dir, "emop_#{name}"),
            }

            operator[:server] = Emissary::Server.new("emop_#{name}", server_data)
            operator[:daemon] = Servolux::Daemon.new(:server => operator[:server])

            # if the daemon is already alive before we've called startup
            # then some other process started it, so we don't bother
            if operator[:daemon].alive? 
              Emissary.logger.warning "Operator '#{name}' already running with pid '#{operator[:daemon].get_pid}'."
              @operators.delete(name)
              next
            end

            operator[:daemon].startup false
            operator[:parent_pid] = retrieve_pid rescue $$
            operator[:daemon_pid] = operator[:daemon].get_pid
            operator[:start_count] += 1

            if operator[:start_count] >= MAX_RESTARTS
              Emissary.logger.warning "Operator '#{name}' has been restarted #{MAX_RESTARTS} times. " +
                                      "I will not attempt to restart it anymore."
            end

            Emissary.logger.notice "Forked Operator '#{name}' with pid #{operator[:daemon_pid]}"
          end
        end

        # if there are no operators left, then there is no point
        # continue - so exit...
        if @operators.length <= 0
          Emissary.logger.notice "No operators left - shutting down." 
          shutdown true
        end

        sleep DAEMON_RECHECK_INTERVAL
      end
    end

    alias :int  :shutdown # handles the INT signal
    alias :term :shutdown # handles the TERM signal
    alias :kill :shutdown # handles the KILL signal
    alias :exit :shutdown # handles the EXIT signal
    alias :hup  :reconfig # handles the HUP signal
    alias :usr1 :restart  # handles the USR1 signal
  end
end
