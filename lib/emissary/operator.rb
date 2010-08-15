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
require 'monitor'
require 'work_queue'

module Emissary
  # ### MONKEY PATCH AHEAD: YOU'VE BEEN WARNED!! ###
  # WorkQueueu oddly loses threads in some weird situation I have figured out yet
  # while using Mutex - switching to Monitor seems to fix it.
  # 
  class WorkQueue < ::WorkQueue
    def initialize *args
      super(*args)
      @threads_lock = Monitor.new if @threads_lock.instance_of? Mutex
    end
  end

  module OperatorStatistics
    RX_COUNT_MUTEX = Mutex.new
    TX_COUNT_MUTEX = Mutex.new
    
    attr_reader :rx_count, :tx_count
    def increment_tx_count
      TX_COUNT_MUTEX.synchronize {
        @tx_count = (@tx_count + 1 rescue 1)
      }
    end
    
    def tx_count
      count = 0
      TX_COUNT_MUTEX.synchronize {
        count = @tx_count
        @tx_count = 0
      }
      count
    end
    
    def increment_rx_count
      RX_COUNT_MUTEX.synchronize {
        @rx_count = (@rx_count + 1 rescue 1)
      }
    end
    
    def rx_count
      count = 0
      RX_COUNT_MUTEX.synchronize {
        count = @rx_count
        @rx_count = 0
      }
      count
    end
  end
  
  class Operator
    include Emissary::OperatorStatistics
    
    DEFAULT_STATUS_INTERVAL = 60
    DEFAULT_MAX_WORKERS     = 50
    MAX_WORKER_TTL          = 60
    
    attr_reader   :config, :shutting_down, :signature 

    # Override .new so subclasses don't have to call super and can ignore
    # connection-specific arguments
    #
    def self.new(config, *args)
      allocate.instance_eval do
        # Store signature
        @signature = config[:signature]

        # Call a superclass's #initialize if it has one
        initialize(config, *args)

        # post initialize callback
        post_init
    
        # set signature nil
        @signature ||= Digest::MD5.hexdigest(config.to_s)
        
        self
      end
    end

    def initialize(config, *args)
      @config    = config
      @workers   = DEFAULT_MAX_WORKERS #args[0][:max_workers] || DEFAULT_MAX_WORKERS rescue DEFAULT_MAX_WORKERS
      @agents    = WorkQueue.new(@workers, nil, MAX_WORKER_TTL)
      @publisher = WorkQueue.new(@workers, nil, MAX_WORKER_TTL)
      @stats     = WorkQueue.new(1, nil, MAX_WORKER_TTL)

      @rx_count  = 0
      @tx_count  = 0

      @shutting_down = false
    end

    def post_init
    end

    def connect
      raise Emissary::Error.new(NotImplementedError, 'The connect method must be defined by the operator module')
    end

    def subscribe
      raise Emissary::Error.new(NotImplementedError, 'The subscrie method must be defined by the operator module')
    end

    def unsubscribe
      raise Emissary::Error.new(NotImplementedError, 'The unsubscribe method must be defined by the operator module')
    end

    def acknowledge message
    end
    
    def reject message, requeue = true
    end
    
    def send_data
      raise Emissary::Error.new(NotImplementedError, 'The send_data method must be defined by the operator module')
    end
    
    def close
      raise Emissary::Error.new(NotImplementedError, 'The close method must be defined by the operator module')
    end

    def run
      connect
      subscribe 
      start_stats_notifier
      send_startup_notification
    end

    def disconnect
      close
    end

    def shutting_down?() @shutting_down; end
    def shutdown!
      @shutting_down = true

      Emissary.logger.notice "Shutting down..."
      send_shutdown_notification

      Emissary.logger.info "Cancelling periodic timer for statistics gatherer..."
      @timer.cancel
      
      Emissary.logger.info "Shutting down agent workqueue..."
      @agents.join

      Emissary.logger.info "Shutting down publisher workqueue..."
      @publisher.join

      Emissary.logger.info "Disconnecting..."
      disconnect
    end

    def enabled? what
      unless [ :startup, :shutdown, :stats ].include? what.to_sym
        Emissary.logger.debug "Testing '#{what}' - it's disabled. Not a valid option."
        return false
      end
      
      unless config[what]
        Emissary.logger.debug "Testing '#{what}' - it's disabled. Missing from configuration."
        return false
      end
      
      if (config[:disable]||[]).include? what.to_s
        Emissary.logger.debug "Testing '#{what}' - it's disabled. Listed in 'disable' configuration option."
        return false
      end
      
      Emissary.logger.debug "Testing '#{what}' - it's enabled.."
      return true
    end
    
    def received message
      acknowledge message
    end

    def rejected message, opts = { :requeue => true }
      reject message, opts
    end
    
    def receive message
      @agents.enqueue_b {
        begin
          Emissary.logger.debug " ---> [DISPATCHER] Dispatching new message ... "
          Emissary.dispatch(message, config, self).activate
          # ack message if need be (operator dependant)
          received message
        rescue Exception => error
          Emissary.logger.error "AgentThread: #{error.message}\n\t#{error.backtrace.join("\n\t")}"
          rejected message, :requeue => true
          send message.error error
        else
          increment_rx_count
        end
        Emissary.logger.debug " ---> [DISPATCHER] tasks/workers: #{@agents.cur_tasks}/#{@agents.cur_threads}"
      }
    end

    def send message
      @publisher.enqueue_b {
        Emissary.logger.debug " ---> [PUBLISHER]  Sending new message ... "
        begin
          unless message.will_loop?
            send_data message
            increment_tx_count
          else
            Emissary.logger.notice "Not sending message destined for myself - would loop."
          end
        rescue Exception => e
          Emissary.logger.error "PublisherThread: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
          shutdown!
        end
        Emissary.logger.debug " ---> [PUBLISHER]  tasks/workers: #{@publisher.cur_tasks}/#{@publisher.cur_threads}"
      }
    end

    def send_startup_notification
      return unless enabled? :startup and EM.reactor_running?   
      Emissary.logger.notice "Sending Startup Notification."
      message = Emissary::Message.new({})
      message.agent   = :emissary
      message.method = :startup
      message.recipient = config[:startup]
      # we receive it and pass it off to the agent who
      # then just sends it off to the correct location
      receive message
    end

    def send_shutdown_notification
      Emissary.logger.notice "Entering shutdown notification..."
      return unless enabled? :shutdown and EM.reactor_running?
      Emissary.logger.notice "Sending Shutdown Notification."
      message = Emissary::Message.new({})
      message.agent   = :emissary
      message.method = :shutdown
      message.recipient = config[:shutdown]
      # we receive it and the agent just resends it off
      # to the correct location
      receive message
    end
    
    def start_stats_notifier
      stats_interval = enabled?(:stats) && config[:stats][:interval] ? config[:stats][:interval].to_i : DEFAULT_STATUS_INTERVAL
      
      # setup agent to process sending of messages
      @timer = EM.add_periodic_timer(stats_interval) do
        rx = rx_count
        tx = tx_count
        rx_throughput = sprintf "%0.4f", (rx.to_f / stats_interval.to_f)
        tx_throughput = sprintf "%0.4f", (tx.to_f / stats_interval.to_f)
        
        Emissary.logger.notice "[METRIC] publisher tasks/workers: #{@publisher.cur_tasks}/#{@publisher.cur_threads}"
        Emissary.logger.notice "[METRIC] dispatcher tasks/workers: #{@agents.cur_tasks}/#{@agents.cur_threads}"
        Emissary.logger.notice "[METRIC] #{tx} in #{stats_interval} seconds - tx rate: #{tx_throughput}/sec"
        Emissary.logger.notice "[METRIC] #{rx} in #{stats_interval} seconds - rx rate: #{rx_throughput}/sec"
        
        unless not enabled? :stats or EM.reactor_running?
          message = Emissary::Message.new({})
          message.agent   = :stats
          message.method = :gather
          receive message          
        end        
      end
    end
  end
end
