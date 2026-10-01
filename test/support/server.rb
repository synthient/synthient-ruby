# frozen_string_literal: true

require "socket"

# A minimal HTTP/1.1 server on 127.0.0.1 with keep-alive. The handler gets
# each request and its socket, and returns [status, headers, body] to send a
# response, or :close after writing raw bytes itself or to drop the
# connection without a response.
class TestServer
  Request = Data.define(:verb, :path, :headers, :body, :connection)

  attr_reader :port

  def initialize(&handler)
    @handler = handler
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @requests = []
    @threads = []
    @mutex = Mutex.new
    @accept = Thread.new { accept_loop }
  end

  def url(path = "/api/v4")
    "http://127.0.0.1:#{@port}#{path}"
  end

  def requests
    @mutex.synchronize { @requests.dup }
  end

  def paths
    requests.map(&:path)
  end

  def close
    @server.close
    @accept.join
    @mutex.synchronize { @threads.dup }.each(&:kill).each(&:join)
  end

  private

  def accept_loop
    connections = 0
    loop do
      socket = @server.accept
      connections += 1
      thread = Thread.new(socket, connections) { |client, id| serve(client, id) }
      @mutex.synchronize { @threads << thread }
    end
  rescue IOError, SystemCallError
    nil
  end

  def serve(socket, connection)
    while (request = read_request(socket, connection))
      @mutex.synchronize { @requests << request }
      response = @handler.call(request, socket)
      break if response == :close

      status, headers, body = response
      headers = headers.transform_keys(&:downcase)
      headers["content-length"] ||= body.bytesize.to_s unless headers.key?("transfer-encoding")
      socket.write("HTTP/1.1 #{status} Status\r\n#{headers.map { |name, value| "#{name}: #{value}\r\n" }.join}\r\n#{body}")
    end
  rescue IOError, SystemCallError
    nil
  ensure
    socket.close
  end

  def read_request(socket, connection)
    line = socket.gets("\r\n") or return nil
    verb, path = line.split
    headers = {}
    while (header = socket.gets("\r\n")) && header != "\r\n"
      name, value = header.split(":", 2)
      headers[name.downcase] = value.strip
    end
    body = headers.key?("content-length") ? socket.read(headers["content-length"].to_i) : ""
    Request.new(verb:, path:, headers:, body:, connection:)
  end
end
