# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"

module Haskimail
  # HTTP transport with JSON (de)serialization, error mapping and retries with
  # exponential backoff and jitter. Thread-safe and fork-safe.
  #
  # Retry policy (designed so that an email is never sent twice):
  # * the TCP/TLS connection could not be opened (DNS, refused, open timeout):
  #   nothing was sent, so any request is retried;
  # * the request may have reached the server (read timeout, reset, 5xx, 429):
  #   only idempotent requests are retried — GET, PUT and explicitly marked
  #   calls. POST (sending!) and DELETE are never retried in this case.
  class Connection
    IDEMPOTENT_METHODS = %w[GET HEAD OPTIONS PUT].freeze

    # Errors from opening the connection (Net::HTTP#start): no request byte was sent.
    CONNECT_ERRORS = [
      Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::EADDRNOTAVAIL,
      Errno::ECONNRESET, Errno::ETIMEDOUT, SocketError, Net::OpenTimeout
    ].freeze

    # Errors while the request was in flight: it may already have been processed.
    TRANSPORT_ERRORS = [
      Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::EADDRNOTAVAIL,
      Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNABORTED, Errno::ETIMEDOUT, SocketError,
      EOFError, IOError, Net::ReadTimeout, Net::WriteTimeout, Net::HTTPBadResponse, Timeout::Error
    ].freeze

    THREAD_KEY = :__haskimail_http_connections

    # A pooled socket idle for longer than this is reopened before use, so that
    # reconnecting happens in the (retry-safe) connect phase instead of inside
    # Net::HTTP#request. Must stay below Net::HTTP#keep_alive_timeout.
    MAX_IDLE_SECONDS = 1.5
    KEEP_ALIVE_TIMEOUT = 2

    # Internal marker: the connection could not be opened (see #open_connection).
    class ConnectFailure < StandardError; end
    private_constant :ConnectFailure

    attr_reader :config

    def initialize(token:, token_header:, config:)
      @token = Secret.new(Util.validate_token!(token, token_header))
      @token_header = token_header
      @config = config
      @base_uri = config.base_uri
      @pool_key = [@base_uri.host, @base_uri.port, config.open_timeout, config.read_timeout,
                   config.write_timeout].freeze
    end

    def get(path, query: nil)
      request(:get, path, query: query)
    end

    def post(path, body = nil, idempotent: false)
      request(:post, path, body: body, idempotent: idempotent)
    end

    def put(path, body = nil, idempotent: true)
      request(:put, path, body: body, idempotent: idempotent)
    end

    def patch(path, body = nil)
      request(:patch, path, body: body, idempotent: true)
    end

    def delete(path)
      request(:delete, path, idempotent: false)
    end

    # @return [Hash, Array, nil] the parsed JSON body (keys as returned by the API)
    def request(method, path, query: nil, body: nil, idempotent: nil)
      verb = method.to_s.upcase
      idempotent = IDEMPOTENT_METHODS.include?(verb) if idempotent.nil?
      uri = build_uri(path, query)
      payload = body.nil? ? nil : JSON.generate(body)
      with_retries(idempotent) { |attempt| send_once(verb, uri, payload, attempt) }
    end

    def inspect
      "#<#{self.class.name} base_url=#{@base_uri} #{@token_header}=#{Util.redact(@token.reveal).inspect}>"
    end
    alias to_s inspect

    private

    def with_retries(idempotent)
      attempt = 0

      begin
        attempt += 1
        yield attempt
      rescue ConnectFailure => e
        retry if retry_after_pause?(attempt)
        raise wrap_network_error(e.cause)
      rescue *TRANSPORT_ERRORS => e
        discard_connection
        retry if idempotent && retry_after_pause?(attempt)
        raise wrap_network_error(e)
      rescue OpenSSL::SSL::SSLError => e
        discard_connection
        # A dropped TLS session may surface as SSLError; certificate problems are never retried.
        retry if idempotent && !e.message.match?(/certificate|verify/i) && retry_after_pause?(attempt)
        raise ConnectionError, "TLS error while talking to Haskimail: #{e.message}"
      rescue ApiError => e
        retry if idempotent && e.retryable? && retry_after_pause?(attempt, e.headers["retry-after"])
        raise
      end
    end

    def build_uri(path, query)
      uri = @base_uri.dup
      uri.path = "#{@base_uri.path.chomp('/')}#{path}"
      params = query&.compact
      uri.query = URI.encode_www_form(params) if params && !params.empty?
      uri
    end

    def send_once(verb, uri, payload, attempt)
      http = open_connection
      response = instrument(verb, uri, attempt) { perform(http, verb, uri, payload) }
      touch_connection
      ResponseHandler.call(response)
    end

    def perform(http, verb, uri, payload)
      request = Net::HTTPGenericRequest.new(verb, !payload.nil?, verb != "HEAD", uri.request_uri)
      default_headers(payload).each { |name, value| request[name] = value }
      request.body = payload if payload
      http.request(request)
    ensure
      close_quietly(http) unless config.persistent_connections
    end

    # Opening the socket is the only phase that is guaranteed to happen before
    # the request is written, so only its failures are marked as safe to retry.
    def open_connection
      config.persistent_connections ? pooled_http : build_http.tap(&:start)
    rescue *CONNECT_ERRORS
      raise ConnectFailure
    end

    def default_headers(payload)
      headers = {
        "Accept" => "application/json",
        "User-Agent" => user_agent,
        @token_header => @token.reveal
      }
      headers["Content-Type"] = "application/json; charset=utf-8" if payload
      headers
    end

    def user_agent
      @user_agent ||= [
        "haskimail-rails/#{VERSION}",
        "ruby/#{RUBY_VERSION}",
        "(#{RUBY_PLATFORM})",
        config.user_agent_suffix
      ].compact.join(" ")
    end

    def build_http
      http = Net::HTTP.new(@base_uri.host, @base_uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.min_version = OpenSSL::SSL::TLS1_2_VERSION
      http.open_timeout = config.open_timeout
      http.read_timeout = config.read_timeout
      http.write_timeout = config.write_timeout
      http.keep_alive_timeout = KEEP_ALIVE_TIMEOUT
      # Net::HTTP silently re-sends idempotent requests (including PUT and
      # DELETE) once after a timeout or reset. Retries are decided here instead.
      http.max_retries = 0
      http
    end

    # One keep-alive connection per thread (more precisely per fiber, since
    # Thread#[] is fiber-local — so concurrent fibers never share a socket) and
    # per endpoint/timeouts. The PID check makes it fork-safe: a Puma/Unicorn
    # worker never reuses its parent's TLS socket. For fiber-per-request servers
    # (Falcon) set persistent_connections = false.
    def pooled_http
      pool = (Thread.current[THREAD_KEY] ||= {})
      pid, http, last_used = pool[@pool_key]
      return http if pid == Process.pid && http&.started? && monotonic_now - last_used < MAX_IDLE_SECONDS

      close_quietly(http) if pid == Process.pid
      pool.delete(@pool_key)
      http = build_http
      http.start
      pool[@pool_key] = [Process.pid, http, monotonic_now]
      http
    end

    def touch_connection
      entry = config.persistent_connections && Thread.current[THREAD_KEY]&.[](@pool_key)
      entry[2] = monotonic_now if entry
    end

    def discard_connection
      return unless config.persistent_connections

      pid, http = Thread.current[THREAD_KEY]&.delete(@pool_key)
      close_quietly(http) if pid == Process.pid
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def close_quietly(http)
      http.finish if http&.started?
    rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
      nil
    end

    def retry_after_pause?(attempt, retry_after = nil)
      return false if attempt > config.max_retries.to_i

      pause(retry_delay(attempt, retry_after))
      true
    end

    def retry_delay(attempt, retry_after)
      max = config.retry_max_delay.to_f
      server_hint = Float(retry_after, exception: false)
      return server_hint.clamp(0.0, max) if server_hint

      exponential = [config.retry_base_delay.to_f * (2**(attempt - 1)), max].min
      (exponential / 2) + (rand * exponential / 2) # "equal jitter"
    end

    def pause(seconds)
      sleep(seconds) if seconds.positive?
    end

    def wrap_network_error(error)
      klass = error.is_a?(Timeout::Error) || error.is_a?(Errno::ETIMEDOUT) ? TimeoutError : ConnectionError
      klass.new("Could not reach Haskimail (#{error.class}: #{error.message})")
    end

    def instrument(verb, uri, attempt)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      payload = { method: verb, path: uri.path, attempt: attempt }
      response = if defined?(ActiveSupport::Notifications)
                   ActiveSupport::Notifications.instrument("request.haskimail", payload) do
                     yield.tap { |res| payload[:status] = res.code.to_i }
                   end
                 else
                   yield
                 end
      log(verb, uri, response.code, started)
      response
    end

    def log(verb, uri, code, started)
      return unless config.logger

      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      config.logger.info("[Haskimail] #{verb} #{uri.path} -> #{code} (#{elapsed}ms)")
    end
  end
end
