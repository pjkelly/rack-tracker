require "rack"
require "tilt"
require "active_support/core_ext/class/attribute"
require "active_support/core_ext/hash"
require "active_support/json"

require "rack/tracker/version"
require "rack/tracker/extensions"
require 'rack/tracker/railtie' if defined?(Rails)
require "rack/tracker/handler"
require "rack/tracker/handler_delegator"
require "rack/tracker/controller"
require "rack/tracker/google_analytics/google_analytics"
require "rack/tracker/facebook/facebook"
require "rack/tracker/vwo/vwo"

module Rack
  class Tracker
    EVENT_TRACKING_KEY = 'tracker'

    def initialize(app, &block)
      @app = app
      @handlers = Rack::Tracker::HandlerSet.new(&block)
    end

    def call(env)
      @status, @headers, @body = @app.call(env)
      return [@status, @headers, @body] unless html?
      response = Rack::Response.new([], @status, @headers)

      env[EVENT_TRACKING_KEY] ||= {}

      if session = env["rack.session"]
        env[EVENT_TRACKING_KEY].deep_merge!(session.delete(EVENT_TRACKING_KEY) || {}) { |key, old, new| Array.wrap(old) + Array.wrap(new) }
      end

      if response.redirection? && session
        session[EVENT_TRACKING_KEY] = env[EVENT_TRACKING_KEY]
      end

      @body.each { |fragment| response.write inject(env, fragment) }
      @body.close if @body.respond_to?(:close)

      response.finish
    end

    private

    def html?; @headers['Content-Type'] =~ /html/; end

    def inject(env, response)
      @handlers.each(env) do |handler|
        response.gsub!(%r{</#{handler.position}>}, handler.render + "</#{handler.position}>")
      end
      response
    end

    class HandlerSet
      class Handler
        def initialize(name, options)
          @name = name
          @options = options
        end

        def init(env)
          @name.new(env, @options)
        end
      end

      def initialize(&block)
        @handlers = []
        self.instance_exec(&block) if block_given?
      end

      def handler(name, opts = {}, &block)
        @handlers << Handler.new(Rack::Tracker::HandlerDelegator.handler(name), opts)
      end

      def each(env = {}, &block)
        @handlers.map{|h| h.init(env)}.each(&block)
      end
    end
  end
end
