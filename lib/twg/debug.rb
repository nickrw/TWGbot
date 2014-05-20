require 'twg/helpers'
require 'twg/plugin'

module TWG
  class Debug < TWG::Plugin
    include Cinch::Plugin

    match /debug ([^ ]+)(?: (.*))?$/, :method => :debug_command

    def self.handler(username, game, core, request, args = nil)
      case request
      when 'minimum'
        if args.nil? or args.empty?
          return "Minimum number of participants is #{game.min_part.inspect}"
        else
          args = args.to_i
          game.min_part = args
          return "Minimum number of participants changed to #{game.min_part.inspect}"
        end
      when 'lang'
        return core.lang.inspect
      when 'state'
        return game.state.inspect
      when 'roles'
        transparency(username, request)
        return game.participants.inspect
      when 'votes'
        transparency(username, request)
        return game.votes.inspect
      else
        return "Unknown request"
      end
    end

    def debug_command(m, request, args = nil)
      u = m.user
      return if not admin?(u)
      response = self.class.handler(u.nick, @game, @core, request, args)
      m.reply response
    end

    private

    def transparency(user, command)
      message = "An administrator just used the \"%s\" debug command (%s)" % [
          command,
          user
      ]
      message = Format(:bold, message)
      @core.chanm(message)
    end

  end
end
