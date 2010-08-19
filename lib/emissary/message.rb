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
require 'uuid'
require 'bert'

module Emissary
  class Message

    attr_accessor :sender, :recipient, :replyto, :errors
    attr_accessor :status, :operation, :thread, :time
    attr_accessor :account, :agent, :method, :args
    attr_reader   :uuid, :originator
    
    def initialize(payload = {})
      @recipient  = ''
      @sender     = Emissary.identity.name
      @replyto    = Emissary.identity.queue_name
      @originator = @sender.dup
      
      @status    = [ :ok, '' ] # tuple of (status type, status message)
      @operation = -1
      @thread    = -1
      @uuid      = UUID.new.generate

      @errors  = []
      
      @agent   = @method = nil
      @account = Emissary.identity.account_id
      @args    = []

      @time = {
        :received => nil,
        :sent     => nil,
      }
      
      payload = {
        :headers => {
          :recipient  => @recipient,
          :sender     => @sender,
          :replyto    => @replyto,
          :originator => @originator,
          :status     => @status, 
          :operation  => @operation,
          :thread     => @thread,
          :uuid       => @uuid,
          :time       => @time.merge((payload[:time].symbolize rescue {})),
        }.merge((payload[:headers].symbolize rescue {})),
        :data   => {
          :account => @account,
          :agent   => @agent,
          :method  => @method,
          :args    => @args
        }.merge((payload[:data].symbolize! rescue {})),
        :errors => [ ] + (payload[:errors].symbolize rescue [])
      }

      payload[:headers].merge(payload[:data]).each do |k,v|
        send("#{k}=".to_sym, v) rescue nil
      end
      
      payload[:errors].each do |e|
        exception = ::Emissary.klass_const(e[:type]).new(e[:message]) rescue StandardError.new("#{e[:type]}: #{e[:message]}")
        exception.set_backtrace(e[:backtrace])
        errors << exception
      end
      
      @agent   = @agent.to_sym rescue nil
      @method  = @method.to_sym rescue nil
      @args    = @args || [] rescue []
    end

    def headers()
      {
        :recipient  => recipient,
        :sender     => sender,
        :replyto    => replyto,
        :originator => originator,
        :status     => status,
        :operation  => operation,
        :thread     => thread,
        :time       => time,
        :uuid       => uuid
      }
    end
    
    def data()
      return { :account => account, :agent => agent, :method => method, :args => args }
    end

    def errors type = :default
      case type
        when :hashes
          @errors.collect do |e|
            { :type => e.class.name, :message => e.message, :backtrace => e.backtrace }
          end
      else
        @errors
      end
    end
    
    def status_type=(t) status[0] = t.to_sym; end
    def status_type() status[0] || :ok rescue :ok; end

    def status_note=(n) status[1] = n; end
    def status_note() status[1] || ''  rescue '' ; end

    def route who = :recipient
      headers[who].split(':') || [] rescue []
    end
    
    def routing_key who = :recipient
      route(who)[0] || nil rescue nil
    end

    def exchange who = :recipient
      [ exchange_type(who), exchange_name(who) ]
    end
    
    def exchange_type who = :recipient
      route(who)[1].to_sym || :direct rescue :direct
    end
    
    def exchange_name who = :recipient
      key, type, name = route(who) rescue [ nil, :direct, 'amq.direct' ]
      name || case type.to_sym
        when :fanout, :topic, :matches, :headers
          "amq.#{type}"
        else
          'amq.direct'
      end
    rescue
      'amq.direct'
    end
    
    def canonical_route who = :recipient
      "#{routing_key(who)}:#{exchange(who).join(':')}"
    end
    
    def will_loop?
      canonical_route(:recipient) == canonical_route(:originator)
    end
    
    def encode
      BERT.encode({ :headers => headers, :data => data, :errors => errors(:hashes) })
    end

    def self.decode payload
      begin
        self.new BERT.decode(payload)
      rescue StandardError => e
        raise e unless e.message =~ /bad magic/i
        Emissary.logger.error "Unable to decode message - maybe it wasn't encoded with BERT..?"
        raise ::Emissary::Error::InvalidMessageFormat, "Unable to decode message - maybe it wasn't encoded with BERT? Message: #{payload.inspect}"
      end
    end

    def stamp_sent!
      time[:sent] = Time.now.to_f
      self
    end
    
    def stamp_received!
      time[:received] = Time.now.to_f
      self
    end
    
    def trip_time
      (time[:sent].to_f - time[:received].to_f rescue 0.0) || 0.0
    end
    
    def response
      header = {
        :recipient => replyto || sender,
        :status    => [ :ok, '' ],
        :operation => operation,
        :thread    => thread,
        :time      => {
          :received => nil,
          :sent     => nil
        }
      }
      return Message.new({ :headers => header, :data => data, :errors => errors(:hashes) })
    end

    def bounce(message = nil)
      message ||= 'Message failed due to missing handler.'
      bounced = self.response
      bounced.status = [ :bounced, message ] 
      return bounced
    end

    def error(message = nil)
      message ||= 'Message failed due to unspecified error.'
      error = self.response
      error.status = [ :errored, message.to_s ]
      if message.is_a? Exception
        error.errors << message
      else
        ::Emissary.logger.warning "#{message.class.name} is not an exception..."
      end
      return error
    end
  end
end
