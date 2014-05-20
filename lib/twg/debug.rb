require 'twg/helpers'
require 'twg/plugin'

module TWG
  class Debug < TWG::Plugin
    include Cinch::Plugin

    match /debug ([^ ]+)(?: (.*))?$/, :method => :debug_command

    def debug_command(m, request, args = nil)
      u = m.user
      return if not admin?(u)
      case request
      when 'minimum'
        args = args.to_i
        @game.min_part = args
        m.reply("Minimum number of participants set to #{@game.min_part.inspect}")
      when 'lang'
        m.reply(@core.lang.inspect)
      when 'state'
        m.reply(@game.state.inspect)
      when 'roles'
        transparency(u, request)
        m.reply(@game.participants.inspect)
      when 'votes'
        transparency(u, request)
        m.reply(@game.votes.inspect)
      else
        m.reply("Unknown request")
      end
    end

    private

    def transparency(user, command)
      message = "An administrator (%s) just used the \"%s\" debug command" % [
          user.nick,
          command
      ]
      message = Format(:bold, message)
      @core.chanm(message)
    end

  end
end
