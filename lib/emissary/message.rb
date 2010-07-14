require 'emissary'
require 'uuid'
require 'bert'

module Emissary
  class Message

    attr_accessor :sender, :recipient, :replyto
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
          :time       => @time.merge((payload[:time].symbolize! rescue {})),
        }.merge((payload[:headers].symbolize! rescue {})),
        :data   => {
          :account => @account,
          :agent   => @agent,
          :method  => @method,
          :args    => @args
        }.merge((payload[:data].symbolize! rescue {}))
      }

      payload[:headers].merge(payload[:data]).each do |k,v|
        send("#{k}=".to_sym, v) rescue nil
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
      BERT.encode({ :headers => headers, :data => data })
    end

    def self.decode payload
      self.new BERT.decode(payload)
    end

    def stamp_sent!
      time[:sent] = Time.now.to_i
      self
    end
    
    def stamp_received!
      time[:received] = Time.now.to_i
      self
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
      return Message.new({ :headers => header, :data => data })
    end

    def bounce(message = nil)
      message ||= 'Message failed due to missing handler.'
      bounced = response()
      bounced.status = [ :bounced, message ] 
      return bounced
    end

    def error(message = nil)
      message ||= 'Message failed due to unspecified error.'
      error = response()
      error.status = [ :errored, message ] 
      return error
    end
  end
end
