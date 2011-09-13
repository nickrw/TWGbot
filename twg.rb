require 'cinch'
require './twg/cinch'

bot = Cinch::Bot.new do
  configure do |c|
    
    c.server = "irc.freenode.org"
    c.channels = ["##testtwg"]
    c.plugins.plugins = [
      TWG::IRC,
      TWG::IRC::Seer,
      TWG::IRC::Debug
    ]
    c.nick = "testtwgbot"
    c.name = "testtwgbot"
    c.user = "testtwgbot"
    c.realname = "testtwgbot"
    c.username = "testtwgbot"
    c.password = "mypassword"
    c.type = :nickserv
    c.ssl.use = true
    c.port = 7000
    c.game = TWG::Game.new
    c.admins = ["mynick"]
    c.game_channel = "##testtwg"
    c.game_timers = {:registration => 30, :day => 60, :night => 60, :dramatic_effect => 5}
    
  end

  on :channel, "!quit" do |m|
    m.user.refresh
    @bot.logger.debug "Shutting down at the request of %s (%s)" % [m.user.nick, m.user.authname]
    exit if @bot.config.admins.include? m.user.authname
  end
end

bot.start


