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
require "mysql"
require "monitor"
require 'timeout'

module Emissary
  class Agent::Mysql < Agent
    DEFAULT_COORDINATES_FILE = '/var/nyt/mysql/master.coordinates'.freeze
    
    def valid_methods
      [ :lock, :unlock, :status ]
    end

    attr_accessor :coordinates_file
    
    def lock(host, user, password, timeout = Agent::Mysql::Helper::DEFAULT_TIMEOUT, coordinates_file = nil)
      @coordinates_file ||= coordinates_file
      @coordinates_file ||= config[:agents][:mysql][:coordinates_file] rescue nil
      @coordinates_file ||= DEFAULT_COORDINATES_FILE
      
      locker = ::Emissary::Agent::Mysql::Helper.new(host, user, password, timeout)
      locker.lock!
        
      filename, position = locker.get_binlog_info
      
      unless filename.nil?
        write_lock_info(filename, position) 
        response = message.response
        response.args = [ filename, position ]
        response.status_note = 'Locked'
      else
        response = message.response
        response.status_note = "No binlog information - can't lock."
      end

      response
    end
    
    def unlock(host, user, password)
      locker = ::Emissary::Agent::Mysql::Helper.new(host, user, password)
      raise "The database was not locked!  (Possibly timed out.)" unless locker.locked?

      locker.unlock!
      
      response = message.response
      response.status_note = 'Unlocked'
      response
    end
    
    def status(host, user, password)
      locker = ::Emissary::Agent::Mysql::Helper.new(host, user, password)
      
      response = message.response
      response.status_note = locker.locked? ? 'Locked' : 'Unlocked'
      response
    end

    private
    
    def write_lock_info(filename, position)
      File.open(coordinates_file, "w") do |file|
        file << "#{filename},#{position}"
      end
    end
    
  end
  
  class Agent::Mysql::Helper
    DEFAULT_TIMEOUT = 30

    @@class_monitor = Monitor.new
    
    # only return one locker per host+user combination
    def self.new(host, user, password, timeout = nil)
      @@class_monitor.synchronize do
        (@@lockers||={})["#{host}:#{user}"] ||= begin
            allocate.instance_eval(<<-EOS, __FILE__, __LINE__)
              initialize(host, user, password, timeout || DEFAULT_TIMEOUT)
              self
            EOS
        end
        @@lockers["#{host}:#{user}"].timeout = timeout unless timeout.nil?
        @@lockers["#{host}:#{user}"]
      end
    end
  
    @@locked_M = Mutex.new
    def locked_M() @@locked_M; end
  
    private 
  
    def initialize(host, user, password, timeout = DEFAULT_TIMEOUT)
      @host       = host
      @user       = user
      @password   = password
      @timeout    = timeout
  
      @watcher    = nil
      @connection = nil
      @locked     = false
    end
  
    
    def connection
      begin
        @connection.ping() unless @connection.nil?
      rescue ::Mysql::Error => e
        if e.message =~ /server has gone away/
          @connection = nil
        else
          raise e
        end
      end
      
      @connection ||= ::Mysql.real_connect(@host, @user, @password)
    end
  
    def disconnect
      unless not connected?
        puts "disconnecting.."
        @connection.close
        @connection = nil
      end
    end
  
    public
    attr_accessor :timeout
    
    def connected?
      !!@connection
    end
  
    # Acquire a lock and, with that lock, run a block/closure.
    def with_lock
      begin
        lock! && yield
      ensure
        unlock!
      end
    end
  
    def locked?
      !!@locked
    end
  
    def lock!
      unless locked?
        kill_watcher_thread! # make sure we have a new thread for watching
        locked_M.synchronize { @locked = true }
        connection.query("FLUSH TABLES WITH READ LOCK")
        spawn_lockwatch_thread!
      end
    end
  
    def unlock!
      begin
        unless not locked?
          locked_M.synchronize {
            connection.query("UNLOCK TABLES")
            @locked = false
          }
        end
      ensure
        disconnect
        kill_watcher_thread!
      end
    end
  
    # Test whether our login info is valid by attempting a database 
    # connection.  
    def valid?
      begin
        !!connection
      rescue => e
        false			# Don't throw an exception, just return false.
      ensure 
        disconnect if connected? 
      end
    end
  
    # Returns [file, position] 
    def get_binlog_info
      raise "get_binlog_info must be called from within a lock." unless locked?
      (result = connection.query("SHOW MASTER STATUS")).fetch_row[0,2]
    ensure
      result.free unless result.nil?
    end
  
    def spawn_lockwatch_thread!
      if @watcher.is_a?(Thread) and not @watcher.alive?
        puts "Watcher is dead - restarting"
        @watcher = nil
      end
      
      @watcher ||= Thread.new {
        begin
          puts "Entering Watcher Loop"
          Timeout.timeout(@timeout) do
            loop { break unless locked? }
          end
        rescue Timeout::Error
        ensure
          unlock!
          Thread.exit
        end
      }
    end
    
    def kill_watcher_thread!
      @watcher.kill unless not @watcher.is_a?(Thread) or not @watcher.alive?
      @watcher = nil
    end
  end
end

