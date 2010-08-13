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
  class Agent
    attr_reader :name, :message, :method, :config, :operator
    attr_accessor :args
    
    def initialize message, config, operator
      @message  = message
      @operator = operator
      @config   = config
      
      @method   = message.method.to_sym rescue :__bad_method__
      @args     = message.args.clone
      
      unless valid_methods.first == :any or valid_methods.include? @method 
        raise ArgumentError, "Invalid method '#{@method.to_s}' for agent '#{message.agent}'"
      end
      
      post_init
    end
  
    def post_init(); end

    def valid_methods
      raise StandardError, 'Not implemented'
    end
    
    def activate
      catch(:skip_implicit_response) do
        result = self.__send__(method, *args)
        response = if not result.kind_of? ::Emissary::Message
          response = message.response
          response.status = [ :ok, (result == true || result.nil? ? 'Succeeded.' : result ) ]
          response
        else
          result
        end
        
        send response
      end
    end
    
    def send message
      operator.send message
    end
  end
end
