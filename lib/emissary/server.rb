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
require 'emissary'
require 'emissary/message'

require 'emissary/servolux'
require 'eventmachine'

module Emissary
  class Server < Servolux::Server
    attr_accessor :active
    
    def initialize(name, opts = {}, &block)
      @active = false
      opts[:logger] = Emissary.logger
      @operator = opts.delete(:operator) or raise Emissary::Error.new(ArgumentError, "Operator not provided")
  
      at_exit { term }    
      super(name, opts, &block)
    end
    
    def active?() !!@active; end
    def activate!() @active = true; end
  
    def term
      @operator.shutdown!
      EM.stop
      exit!(0)
    end

    alias :int :term

    # override Servolux::Server's startup because we don't need threaded here.  
    def startup
      return self if active?

      begin
        create_pid_file
        trap_signals
        run
      ensure
        delete_pid_file
      end
      return self
    end

    def run
      return if active?
      
      EM.run {
        begin
          $0 = @name
          logger.info "Starting up new Operator process"
          @operator.run
          activate!
        rescue Exception => e
          Emissary.logger.error "Server '#{$0}': #{e.message}\n\t#{e.backtrace.join("\n\t")}"
          term
        end
      }
    end

  end
end
