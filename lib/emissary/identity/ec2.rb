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
  class Identity::Ec2 < Identity
    register :ec2, :priority => 25

    QUERY_IP         = '169.254.169.254'
    INSTANCE_ID_PATH = '/latest/meta-data/instance-id'
    LOCAL_IPV4_PATH  = '/latest/meta-data/local-ipv4'
    PUBLIC_IPV4_PATH = '/latest/meta-data/public-ipv4'

    def initialize
      @instance_id = nil
      @local_ipv4  = nil
      @public_ipv4 = nil
    end
    
    def instance_id
      @instance_id ||= get(INSTANCE_ID_PATH)
    end

    alias :queue_name :instance_id
    
    def local_ip
      @local_ipv4 ||= get(LOCAL_IPV4_PATH)
    end

    def public_ip
      @public_ipv4 ||= get(PUBLIC_IPV4_PATH)
    end
    
    private
    
    def get uri
      begin
        http = Net::HTTP.new(QUERY_IP)
        http.open_timeout = 0.5 
        http.read_timeout = 0.5
        http.start do |http|
          http.get(uri).body
        end
      rescue Exception
        throw :pass
      end
    end
  end
end
