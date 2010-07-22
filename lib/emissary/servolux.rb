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
require 'servolux'

# monkey patches for servolux
class Servolux::Daemon
  # provide pid to external libraries
  def get_pid() retrieve_pid; end
  def alive?
    pid = retrieve_pid
    Process.kill(0, pid)
    true
  rescue TypeError # don't fail on nil being passed to kill
    # usually means pid was nil, so return false
    false
  rescue Errno::ESRCH, Errno::ENOENT
    false
  rescue Errno::EACCES => err
    logger.error "You do not have access to the PID file at " \
                 "#{pid_file.inspect}: #{err.message}"
    false
  end
end

class Servolux::Piper
  def initialize( *args )
    opts = args.last.is_a?(Hash) ? args.pop : {}
    mode = args.first || 'r'

    unless %w[r w rw].include? mode
      raise ArgumentError, "Unsupported mode #{mode.inspect}"
    end

    @timeout = opts.key?(:timeout) ? opts[:timeout] : nil
    socket_pair = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
    @child_pid = Kernel.fork

    if child?
      @socket = socket_pair[1]
      socket_pair[0].close

      case mode
      when 'r'; @socket.close_read
      when 'w'; @socket.close_write
      end
    else
      # prevent zombie processes - register disinterest
      # in return status of child process
      Process.detach @child_pid

      @socket = socket_pair[0]
      socket_pair[1].close

      case mode
      when 'r'; @socket.close_write
      when 'w'; @socket.close_read
      end

    end
  end
end

