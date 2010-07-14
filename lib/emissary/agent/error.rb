require 'emissary/agent'

module Emissary
  class Agent::Error < Agent
    def valid_methods
      [ :any ]
    end
		
    def activate
      message
    end
  end
end
