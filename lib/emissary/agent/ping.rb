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
