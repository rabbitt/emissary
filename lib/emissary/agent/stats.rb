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
require 'emissary/agent'

module Emissary
  class Agent::Stats < Agent    
    STATISTIC_TYPES = [ :cpu, :network, :disk ]

    begin
      require 'sys/cpu'
    rescue LoadError
      STATISTIC_TYPES.delete(:cpu)
      ::Emissary.logger.warning "Ruby Gem 'sys-cpu' doesn't appear to be present - removing statistic gather for cpu."
    end
    
    begin
      require 'ifconfig' 
    rescue LoadError
      STATISTIC_TYPES.delete(:network)
      ::Emissary.logger.warning "Ruby Gem 'ifconfig' doesn't appear to be present - removing statistic gather for network."
    end

    def valid_methods
      [ :gather ]
    end
    
    def gather
      message.recipient = config[:stats][:queue_base]
      STATISTIC_TYPES.each do |type|
        stat_message = message.clone
        stat_message.recipient = "#{message.routing_key}.#{type.to_s}:#{message.exchange_type.to_s}"
        stat_message.args = self.__send__(type) unless not self.respond_to? type
        send stat_message unless stat_message.args.empty?
      end

      throw :skip_implicit_response
    end
    
    def cpu
      Sys::CPU.load_avg
    end
    
    def network
      data = {}
      (ifconfig = IfconfigWrapper.new.parse).interfaces.each do |iface|
        data[iface] = {
          :tx  => ifconfig[iface].tx,
          :rx  => ifconfig[iface].rx,
          :up  => ifconfig[iface].status,
          :ips => ifconfig[iface].addresses('inet').collect { |ip| ip.to_s }
        }
      end
      
      return [ data ]
    end
  end
end
