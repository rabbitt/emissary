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
require 'escape'

module Emissary
  class Agent::Rabbitmq < Agent
    NIMBUL_VHOST    = '/nimbul'

    NODE_CONFIG_ACL = '^i-[a-f0-9.]+$'
    NODE_READ_ACL   = '^(amq.*|i-[a-f0-9.]+|request.%%ID%%.*)$'
    NODE_WRITE_ACL  = '^(amq.*|i-[a-f0-9.]+|(startup|info|shutdown).%%ID%%.*|nimbul)$'
    
    QUEUE_INFO_ITEMS = %w[
        name durable auto_delete arguments pid owner_pid
        exclusive_consumer_pid exclusive_consumer_tag
        messages_ready messages_unacknowledged messages_uncommitted
        messages acks_uncommitted consumers transactions memory      
    ]
    
    EXCHANGE_INFO_ITEMS = %w[
      name type durable auto_delete arguments
    ]
    
    CONNECTION_INFO_ITEMS = %w[
        pid address port peer_address peer_port state channels user
        vhost timeout frame_max client_properties recv_oct recv_cnt
        send_oct send_cnt send_pend
    ]
    
    CHANNEL_INFO_ITEMS = %w[
      pid connection number user vhost transactional consumer_count
      messages_unacknowledged acks_uncommitted prefetch_count
    ]
    
    BINDINGS_INFO_COLUMNS = %w[ exchange_name queue_name routing_key arguments ]
    CONSUMER_INFO_COLUMNS = %w[ queue_name channel_process_id consumer_tag must_acknowledge ]
    
    class CommandExecutionError < StandardError; end

    def valid_methods
      [
        :add_user,
        :delete_user,
        :change_password,
        :list_users,
        
        :add_vhost,
        :delete_vhost,
        :list_vhosts,
        
        :add_node_account,
        :del_node_account,
        
        :list_user_vhosts,
        :list_vhost_users,
        
        :list_queues,
        :list_bindings,
        :list_exchanges,
        :list_connections,
        :list_channels,
        :list_consumers
      ]
    end
  
    def list_queues(vhost)
      vhost = vhost.empty? ? '/' : vhost
      rabbitmqctl(:list_queues, '-p', vhost, QUEUE_INFO_ITEMS.join(" ")).collect do |line|
        Hash[*QUEUE_INFO_ITEMS.zip(line.split(/\s+/)).flatten]
      end
    end
    
    def list_bindings(vhost)
      vhost = vhost.empty? ? '/' : vhost
      rabbitmqctl(:list_bindings, '-p', vhost).collect do |line|
        Hash[*BINDINGS_INFO_COLUMNS.zip(line.split(/\s+/)).flatten]
      end
    end

    def list_exchanges(vhost)
      vhost = vhost.empty? ? '/' : vhost
      rabbitmqctl(:list_exchanges, '-p', vhost, EXCHANGE_INFO_ITEMS.join(" ")).collect do |line|
        Hash[*EXCHANGE_INFO_ITEMS.zip(line.split(/\s+/)).flatten]
      end
    end
      
    def list_connections
      rabbitmqctl(:list_connections, CONNECTION_INFO_ITEMS.join(" ")).collect do |line|
        Hash[*CONNECTION_INFO_ITEMS.zip(line.split(/\s+/)).flatten]
      end
    end
      
    def list_channels
      rabbitmqctl(:list_channels, CHANNEL_INFO_ITEMS.join(" ")).collect do |line|
        Hash[*CHANNEL_INFO_ITEMS.zip(line.split(/\s+/)).flatten]
      end
    end
    
    def list_consumers(vhost)
      vhost = vhost.empty? ? '/' : vhost
      rabbitmqctl(:list_consumers, '-p', vhost).collect do |line|
        Hash[*CONSUMER_INFO_COLUMNS.zip(line.split(/\s+/)).flatten]
      end
    end

    def list_users
      rabbitmqctl(:list_users)
    end
    
    def list_vhosts
      rabbitmqctl(:list_vhosts)
    end
    
    def list_vhost_users(vhost)
      vhost = vhost.empty? ? '/' : vhost
      rabbitmqctl(:list_permissions, '-p', vhost).flatten.select { |l|
        !l.nil?
      }.collect {
        |l| l.split(/\s+/)[0]
      }
    end
    
    def list_user_vhosts(user)
      list_vhosts.select { |vhost| list_vhost_users(vhost).include? user }
    end

    def set_vhost_permissions(user, vhost, config, write, read)
      vhost = vhost.empty? ? '/' : vhost
      rabbitmqctl(:set_permissions, '-p', vhost, user, config, write, read)
    end
    
    def del_vhost_permissions(user, vhost)
      vhost = vhost.empty? ? '/' : vhost
      rabbitmqctl(:clear_permissions, '-p', vhost, user)
    end

    def add_node_account_acl(user, namespace_id)
      config_acl = NODE_CONFIG_ACL.gsub('%%ID%%', namespace_id.to_s)
      write_acl  = NODE_WRITE_ACL.gsub('%%ID%%', namespace_id.to_s)
      read_acl   = NODE_READ_ACL.gsub('%%ID%%', namespace_id.to_s)
      
      begin      
        set_vhost_permissions(user, NIMBUL_VHOST, config_acl, write_acl, read_acl)
      rescue CommandExecutionError => e
        "problem adding account acls for user: #{user}: #{e.message}"
      else
        "successfully added account acls for user: #{user}"
      end
    end

    def add_node_account(user, password, namespace_id)
      begin
        add_user(user, password)
        add_node_account_acl(user, namespace_id.to_s)
      rescue CommandExecutionError => e
        "failed to add new node account: #{user}:#{namespace_id.to_s}"
      end
    end
    
    def del_node_account_acl(user, vhost)
      begin
        del_vhost_permissions(user, vhost)
      rescue CommandExecutionError => e
        "problem unmapping user from vhost: #{user}:#{vhost} #{e.message}"
      else
        "successfully unmapped user from vhost: #{user}:#{vhost}"
      end
    end
  
    def add_vhost(path)
      begin
        !!rabbitmqctl(:add_vhost, path)
      rescue CommandExecutionError => e
        raise e unless e.message.include? 'vhost_already_exists'
      end
    end
    
    def add_user(user, pass)
      begin
        !!rabbitmqctl(:add_user, user, pass)
      rescue CommandExecutionError => e
        raise e unless e.message.include? 'user_already_exists'
      end
    end
    
    def change_password(user, pass)
      begin
        !!rabbitmqctl(:change_password, user, pass)
      rescue CommandExecutionError => e
        return false if e.message.include? 'no_such_user'
        raise e 
      end
    end
    
    def delete_user(user)
      begin
        !!rabbitmqctl(:delete_user, user)
      rescue CommandExecutionError => e
        raise e unless e.message.include? 'no_such_user'
      end
    end
    
    def delete_vhost(path)
      begin
        !!rabbitmqctl(:delete_vhost, path)
      rescue CommandExecutionError => e
        raise e unless e.message.include? 'no_such_vhost'
      end
    end

    def rabbitmqctl(*args)
      result = []
      `rabbitmqctl #{Escape.shell_command([*args.collect{|a| a.to_s}])} 2>&1`.each do |line|
        raise CommandExecutionError, $1 if line =~ /Error: (.*)/
        result << line.chomp unless line =~ /\.\.\./
      end
      result
    end
  end
end