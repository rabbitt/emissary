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
  class Agent::Test < Agent
    def valid_methods
      [:test_raise]
    end
    
    def test_raise klass, *args
      ::Emissary.logger.debug "TEST AGENT: #test(#{klass}, #{args.inspect})"

      exception = nil
      begin
        e_klass = ::Emissary.klass_const(klass)
        unless not e_klass.try(:new).try(:is_a?, Exception)
          raise e_klass, *args
        else
          raise Exception, "#{e_klass.name.to_s} is not a valid exception!"
        end
      rescue Exception => e
        exception = e
      end

      message.error exception
    end
  end
end
