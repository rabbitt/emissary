require 'emissary/agent'

module Emissary
  class Agent::Proxy < Agent
    def valid_methods
      [ :any ]
    end
		
    def activate
      throw :skip_implicit_response 
    end
  end
end
