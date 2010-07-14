require 'emissary/agent'

module Emissary
  class Agent::File < Agent
    def valid_methods
      [ :any ]
    end
		
    def activate
      throw :skip_implicit_response 
    end
  end
end
