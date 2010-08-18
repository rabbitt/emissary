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
      message.recipient = "#{config[:stats][:queue_base]}:#{message.exchange_type.to_s}"
      message.args = STATISTIC_TYPES.inject([]) do |args, type|
        unless (data = self.__send__(type)).nil?
          args << { type => data }
        end
        args
      end

      throw :skip_implicit_response unless not message.args.empty?
      return message
    end

    def disk
    end
    
    def cpu
      load_average = Sys::CPU.load_avg
      ::Emissary.logger.notice "[statistics] CPU: #{load_average.join ', '}"
      load_average
    end
    
    def network
      interfaces = (ifconfig = IfconfigWrapper.new.parse).interfaces.inject([]) do |interfaces, name|
        interfaces << (interface = {
          :name => name,
          :tx   => ifconfig[name].tx.symbolize,
          :rx   => ifconfig[name].rx.symbolize,
          :up   => ifconfig[name].status,
          :ips  => ifconfig[name].addresses('inet').collect { |ip| ip.to_s }
        })
        
        ::Emissary.logger.notice("[statistics] Network#%s: state:%s tx:%d rx:%d inet:%s",
          name,
          (interface[:up] ? 'up' : 'down'),
          interface[:tx][:bytes],
          interface[:rx][:bytes],
          interface[:ips].join(',')
        ) unless interface.try(:[], :tx).nil?
        
        interfaces
      end
      
      return interfaces
    end
  end
end
