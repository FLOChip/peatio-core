module Peatio::Ranger
  class Connection
    def initialize(socket, logger)
      @socket = socket
      @logger = logger
      @streams = []
    end

    def send(method, data)
      payload = JSON.dump(method => data)
      @logger.debug { payload }
      @socket.send payload
    end

    def handle(msg)
      data = JSON.parse(msg)
      @client.user = data[:uid]
      @client.authorized = true

      @logger.info "ranger: user #{@client.user} authenticated #{@streams}"

      send :success, message: "Authenticated."
    end

    def handshake(handshake)
      query = URI::decode_www_form(handshake.query_string)

      @streams = query.map do |item|
        if item.first == "stream"
          item.last
        end
      end

      @logger.info "ranger: WebSocket connection openned, streams: #{@streams}"

      @client = Peatio::MQ::Events::Client.new(
        @socket, @streams,
      )

      @socket.instance_variable_set(:@connection_handler, @client)
    end
  end

  def self.run!
    host = ENV["RANGER_HOST"] || "0.0.0.0"
    port = ENV["RANGER_PORT"] || "8081"

    logger = Peatio::Logger.logger
    logger.info "Starting the server on port #{port}"

    EM.run do
      Peatio::MQ::Client.new
      Peatio::MQ::Client.connect!
      Peatio::MQ::Client.create_channel!

      Peatio::MQ::Events.subscribe!

      EM::WebSocket.start(
        host: host,
        port: port,
        secure: false,
      ) do |socket|
        connection = Connection.new(socket, logger)

        socket.onopen do |handshake|
          connection.handshake(handshake)
        end

        socket.onmessage do |msg|
          connection.handle(msg)
        end

        socket.onclose do
          logger.info "ranger: WebSocket connection closed"
        end

        socket.onerror do |e|
          logger.error "ranger: WebSocket Error: #{e.message}"
        end
      end

      yield if block_given?
    end
  end
end
