#
# $Id $
# author: Carl P. corliss
# Copyright 2009, The New York Times
#
require 'syslog'
require 'fastthread'

module Emissary
	class Logger
		
		LOG_SYSLOG = 0x01
		LOG_STDOUT = 0x02
    LOG_STDERR = 0x03

    EMERGENCY = Syslog::Constants::LOG_EMERG
    EMERG     = Syslog::Constants::LOG_EMERG
    ALERT     = Syslog::Constants::LOG_ALERT
    FATAL     = Syslog::Constants::LOG_CRIT
    CRITICAL  = Syslog::Constants::LOG_CRIT
    CRIT      = Syslog::Constants::LOG_CRIT
    ERROR     = Syslog::Constants::LOG_ERR
    ERR       = Syslog::Constants::LOG_ERR
    WARNING   = Syslog::Constants::LOG_WARNING
    WARN      = Syslog::Constants::LOG_WARNING
    NOTICE    = Syslog::Constants::LOG_NOTICE
    INFO      = Syslog::Constants::LOG_INFO
    DEBUG     = Syslog::Constants::LOG_DEBUG
    
    CONSTANT_ID_MAP = {
      EMERGENCY => [ :emergency, :emerg ],
      ALERT     => [ :alert ],
      CRITICAL  => [ :fatal, :critical, :crit ],
      ERROR     => [ :error, :err ],
      WARNING   => [ :warning, :warn ],
      NOTICE    => [ :notice ],
      INFO      => [ :info ],
      DEBUG     => [ :debug ]
    }

    CONSTANT_NAME_MAP = CONSTANT_ID_MAP.inject({}) do |mappings,(id,names)|
      names.each { |name| mappings.merge!({ name => id, name.to_s.upcase => id, name.to_s.downcase => id }) }
      mappings
    end

    attr_accessor :mode, :level, :name
    
		def self.instance(mode = LOG_STDERR, log_level = NOTICE, name = nil)
			@@logger ||= Emissary::Logger.new mode, log_level
		end

		private :initialize
		
		def initialize mode, log_level, name = nil
			@mode  = mode || LOG_STDERR
			@level = log_level || INFO
      @name  = name
      @mutex = Mutex.new
		end

    def name=(p) @name = n || File.basename($0); end
    
    def normalize log_level
      return log_level unless not log_level.kind_of? Fixnum
      return CONSTANT_NAME_MAP[log_level.to_s.downcase] rescue INFO
      return INFO
    end
    
		def loggable?(log_level)
			log_level <= normalize(@level)
		end

    def syslogger
      @mutex.synchronize {
        Syslog.open(name, Syslog::LOG_PID | Syslog::LOG_NDELAY, Syslog::LOG_DAEMON) do |s|
          s.LOG_UPTO(level)
          yield s
        end
      }
    end      
		
		def log(log_level, message, *args)
			case @mode
				when Logger::LOG_SYSLOG
          messages = "#{CONSTANT_ID_MAP[log_level].first.to_s.upcase}: #{message}".gsub(/\t/, ' '*8).split(/\n/)
          # some syslog daemons have a hard time with newlines, so split into multiple lines
					messages.each do |message|
            syslogger { |s| s.log(log_level, message, *args) }
					end
				when Logger::LOG_STDOUT
					$stdout << sprintf(message << "\n", *args) unless not loggable? log_level
				when Logger::LOG_STDERR
					$stderr << sprintf(message << "\n", *args) unless not loggable? log_level
			end
			
			self
		end

		for log_level in [:emergency, :emerg, :alert, :critical, :crit, :fatal, :error, :err, :warning, :warn, :notice, :info, :debug]
			class_eval %(
				def #{log_level}(message, *args)
					log(#{'::Emissary::Logger::' + log_level.to_s.upcase}, message, *args)
				end
			)
		end
	end
end
