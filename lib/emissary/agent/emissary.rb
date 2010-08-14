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
require 'emissary/gem'
require 'tempfile'
require 'fileutils'

module Emissary
  class Agent::Emissary < Agent
    def valid_methods
      [ :reconfig, :selfupdate, :startup, :shutdown ]
    end
    
    def reconfig new_config
      throw :skip_implicit_response if new_config.strip.empty?
      
      if (test(?w, config[:agents][:emissary][:config_path]))
        begin
          ((tmp = Tempfile.new('new_config')) << new_config).flush
          Emissary::Daemon.get_config(tmp.path)
        rescue Exception => e
          resonse = message.response
          response.status_type = :error
          response.status_note = e.message
          return response
        else
          FileUtils.mv tmp.path, config[:agents][:emissary][:config_path]
          # signal a USR1 to our parent, which will cause it to kill the
          # children and restart them after rereading it's configuration
          Process.kill('HUP', config[:parent_pid])
        ensure
          tmp.close
        end
      end      

    end

    def selfupdate version = :latest, source_url = :default
      with_detached_process do 
        require 'emissary/agent/gem'
        begin
          ::Emissary::Gem.new('emissary').update(version, source_url)
        rescue ::Gem::InstallError, ::Gem::GemNotFoundException => e
          response = message.response
          response.status_type = :error
          response.status_note = e.message
          return response
        else
          with_detached_process do 
            %x{
                emissary stop
                # now make sure that it is stopped after giving it 5 seconds to shutdown
                sleep 5 
                ps uxa | grep -v grep | grep '(emissary|emop_)' | awk '{ print $2 }' | xargs kill -9
                emissary start -d
              }
          end
          throw :skip_implicit_response
        end
      end
    end
    
    def startup
      message.recipient = config[:startup]
      message.args = [
        ::Emissary.identity.name,
        ::Emissary.identity.public_ip,
        ::Emissary.identity.local_ip,
        ::Emissary.identity.instance_id,
        ::Emissary.identity.server_id,
        ::Emissary.identity.cluster_id,
        ::Emissary.identity.account_id,
        ::Emissary.identity.queue_name,
      ]

      ::Emissary.logger.notice "Sending Startup message with args: #{message.args.inspect}"

      message
    end
    
    def shutdown
      message.recipient = config[:shutdown]
      message.args = [
        ::Emissary.identity.server_id,
        ::Emissary.identity.cluster_id,
        ::Emissary.identity.account_id,
        ::Emissary.identity.instance_id
      ]
      ::Emissary.logger.notice "Sending Shutdown message with args: #{message.args.inspect}"
      message
    end

private

    def with_detached_process
      raise Exception, 'Block missing for with_detached_process call' unless block_given?
      
      # completely seperate from our parent process
      pid = Kernel.fork do
        Process.setsid
        exit!(0) if fork 
        Dir.chdir '/'
        File.umask 0000
        STDIN.reopen  '/dev/null' 
        STDOUT.reopen '/dev/null', 'a' 
        STDERR.reopen '/dev/null', 'a'
        yield
      end

      #don't worry about      
      Process.detach(pid)
    end
  end
end
