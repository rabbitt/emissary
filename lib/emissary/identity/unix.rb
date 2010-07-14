require 'emissary/identity'

module Emissary
  class Identity::Unix < Identity
    # defaults to priority 0 (which means, it's the last option if nothing else takes it)
    register :unix 

    def name
      @hostname ||= `hostname`.strip
    end

    alias :queue_name :name

    def roles
      ENV['ROLES'] || ''
    end
    
    def instance_id
      ENV['INSTANCE_ID'] || -1
    end
    
    def server_id
      ENV['SERVER_ID'] || -1
    end
    
    def cluster_id
      ENV['CLUSTER_ID'] || -1
    end

    def account_id
      ENV['ACCOUNT_ID'] || -1
    end
    
    def local_ip
      @ip_local ||= begin
        # turn off reverse DNS resolution temporarily
        orig, Socket.do_not_reverse_lookup = Socket.do_not_reverse_lookup, true  
        @ip_local = UDPSocket.open { |s| s.connect IP_CHECK_DOMAIN, 1; s.addr.last }
      rescue
        nil
      ensure
        Socket.do_not_reverse_lookup = orig rescue nil
      end
    end
  
    def public_ip
      @ip_public ||= begin
        Net::HTTP.get(URI.parse(IP_CHECK_URL)).gsub(/.*?((\d{1,3}\.){3}\d{1,3}).*/m, '\1')
      rescue
        nil
      end
    end
  end
end
