require 'socket'
require 'twg/helpers'
require 'twg/plugin'

module TWG
  class Socket < TWG::Plugin
    include Cinch::Plugin
    listen_to :create_socket, :method => :create_socket

    def initialize(*args)
      super
      hook_async(:create_socket)
    end

    def create_socket(m=nil)

      ::Socket.tcp_server_loop('localhost', 2000) do |sock, client|
        Thread.new do

          begin

            continue = false
            sock.puts "HELLO"
            loop do
              res = dispatch_socket_input(sock)
              continue = true if res[:loop] == :multiple
              break if res[:loop] == :break
              break if not continue
            end

          ensure
            sock.close
          end

        end
      end

    end

    private

    def parse_socket_input(socketline)
      raise ArgumentError if socketline.class != String
      socketline.strip!
      args = socketline.split(" ")
      command = args.shift.downcase.to_sym
      puts "%s -> %s " % [command, args]
      return {:command => command, :args => args}
    end

    def dispatch_socket_input(socket)
      res = parse_socket_input(socket.gets)

      case res[:command]
      when :help
        socket.puts "Commands: help, multiple, say, hook, quit"
      when :multiple
        socket.puts "OK now in multiple-command mode"
        res[:loop] = :multiple
      when :quit
        socket.puts "OK bye"
        res[:loop] = :break
      when :say
        message = res[:args].join(" ")
        @core.chanm(message)
        socket.puts "OK said %s" % res[:args].join(" ")
      when :hook
        hook = res[:args].shift
        if hook.class != String
          socket.puts "ERR invalid hook"
          return res
        end
        hook = hook.downcase.to_sym
        args = res[:args]
        hook_async(hook, 0, nil, *args)
        socket.puts "OK triggered hook %s" % hook.to_s
      when :debug
        args = res[:args]
        debug_command = args.shift
        response = TWG::Debug.handler(
          "via local socket",
          @game,
          @core,
          debug_command,
          args.join(" ")
        )
        socket.puts "DBG %s" % response
      else
        socket.puts "ERR unrecognised command %s" % res[:command].to_s
      end

      return res
    end

  end
end

