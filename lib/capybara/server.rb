require 'uri'
require 'net/http'
require 'rack'

module Capybara
  class Server
    class Middleware
      attr_accessor :error

      def initialize(app)
        @app = app
      end

      def call(env)
        if env["PATH_INFO"] == "/__identify__"
          [200, {}, [@app.object_id.to_s]]
        else
          begin
            @app.call(env)
          rescue StandardError => e
            @error = e unless @error
            raise e
          end
        end
      end
    end

    class << self
      def ports
        @ports ||= {}
      end
    end

    attr_reader :app, :port

    def initialize(app, port=Capybara.server_port)
      @app = app
      @middleware = Middleware.new(@app)
      @server_thread = nil # supress warnings
      @port = port
      @port ||= Capybara::Server.ports[@app.object_id]
      @port ||= find_available_port
    end

    def reset_error!
      @middleware.error = nil
    end

    def error
      @middleware.error
    end

    def host
      Capybara.server_host || "127.0.0.1"
    end

    def responsive?
      return false if @server_thread && @server_thread.join(0)

      res = Net::HTTP.start(host, @port) { |http| http.get('/__identify__') }

      if res.is_a?(Net::HTTPSuccess) or res.is_a?(Net::HTTPRedirection)
        return res.body == @app.object_id.to_s
      end
    rescue Errno::ECONNREFUSED, Errno::EBADF
      return false
    end

    def boot
      unless responsive?
        Capybara::Server.ports[@app.object_id] = @port

        @server_thread = Thread.new do
          Capybara.server.call(@middleware, @port)
        end

        Timeout.timeout(60) { @server_thread.join(0.1) until responsive? }
      end
    rescue TimeoutError
      raise "Rack application timed out during boot"
    else
      self
    end

  private

    def find_available_port
      server = TCPServer.new('127.0.0.1', 0)
      server.addr[1]
    ensure
      server.close if server
    end

  end
end
