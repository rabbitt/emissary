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
