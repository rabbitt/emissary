require 'emissary/agent'

module Emissary
  class Agent::Ping < Agent
    def valid_methods
      [:ping, :pong]
    end
    
    def ping
      reply = message.response
      reply.method = :pong

      ::Emissary.logger.debug "Received PING: originator: #{message.originator}"
      ::Emissary.logger.debug "Sending PONG : originator: #{reply.originator}"

      reply
    end
    
    def pong
      ::Emissary.logger.debug "Received PONG"
      throw :skip_implicit_response
    end
  end
end
