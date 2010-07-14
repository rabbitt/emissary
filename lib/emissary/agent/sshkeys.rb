require 'emissary/agent'

require 'digest/md5'
require 'base64'
require 'etc'

module Emissary
  class Agent::Sshkeys < Agent
    AUTH_KEY_FILE = '.ssh/authorized_keys'

    attr_reader :user
    
    def valid_methods
      [ :add, :delete, :update ]
    end
    
    def post_init
      begin
        @user = Etc.getpwnam(args.shift)
      rescue ArgumentError => e
        if e.message =~ /can't find user/
          raise "User '#{args.first}' does not exist on this system"
        else
          raise "Unhandled error attempting to retrieve data on user [#{args.first}]: #{e.message}"
        end
      end
    end
    
    def add pubkey
      raise "Missing 'key_uri' argument - can't download key!" if pubkey.nil?

      pubkey_name = Digest::MD5.hexdigest(pubkey.split(/\s+/).join(' ').chomp)

      begin
        keys = get_keys(user)
        if not keys.has_key?(pubkey_name)
          keys[pubkey_name] = pubkey
          write_keys(user, keys)
          result = "Successfully added key [#{pubkey_name}] to user [#{user.name}]"
        else
          result = "Could not add key [#{pubkey_name}] to user [#{user.name}] - key already exists!"
        end
      rescue Exception => e
        raise Exception, 'Possibly unable to add user key - error was: ' + e.message, caller
      end

      return result
    end
    
    def delete pubkey
      return 'No authorized_keys file - nothing changed' if not File.exists?(File.join(user.dir, AUTH_KEY_FILE))
  
      keyname = Digest::MD5.hexdigest(pubkey)
      begin
        keys = get_keys(user)
        if keys.has_key?(keyname)
          keys.delete(keyname)
          write_keys(user, keys)
          result = "Successfully removed key [#{keyname}] from user [#{user.name}]"
        else
          result = "Could not remove key [#{keyname}] from user [#{user.name}] - key not there!"
        end
      rescue Exception => e
        raise "Possibly unable to remove key #{keyname} for user #{user.name} - error was: #{e.message}"
      end
  
      return result
    end

    def update oldkey, newkey
      return 'Not implemented'
    end
    
    private
    
    def write_keys(user, keys)
      auth_file_do(user, 'w') do |fp|
        fp << keys.values.join("\n")
      end
    end
  
    def get_keys(user)
      ::Emissary.logger.debug "retreiving ssh keys from file #{File.join(user.dir, AUTH_KEY_FILE)}"
  
      keys = {}
      auth_file_do(user, 'r') do |fp|
        fp.readlines.each do |line|
          keys[Digest::MD5.hexdigest(line.chomp)] = line.chomp
        end
      end
  
      return keys
    end
  
    def auth_file_setup(user)
      user_auth_file = File.join(user.dir, AUTH_KEY_FILE)
      user_ssh_dir   = File.dirname(user_auth_file)
  
      begin
        if not File.directory?(user_ssh_dir)
          Dir.mkdir(user_ssh_dir)
          File.open(user_ssh_dir) do |f|
            f.chown(user.uid, user.gid)
            f.chmod(0700)
          end
        end
        if not File.exists?(user_auth_file)
          File.open(user_auth_file, 'a') do |f|
            f.chown(user.uid, user.gid)
            f.chmod(0600)
          end
        end
      rescue Exception => e
        raise "Error creating #{user_auth_file} -- #{e.message}"
      end
  
      return user_auth_file
    end
  
    def auth_file_do(user, mode = 'r', &block)
      begin
        auth_file = auth_file_setup(user)
        File.open(auth_file, mode) do |f|
          f.flock File::LOCK_EX
          yield(f)
          f.flock File::LOCK_UN
        end
      rescue Exception => e
        case mode
          when 'r': mode = 'reading from'
          when 'a': mode = 'appending to'
          when 'w': mode = 'writing to'
          else mode = "unknown operation #{mode} for File.open() on "
        end
        raise "Error #{mode} file '#{auth_file}' --  #{e.message}"
      end
    end
  end
end
