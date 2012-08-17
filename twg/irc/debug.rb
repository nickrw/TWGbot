class Debug
  include Cinch::Plugin
  listen_to :channel
  match /debug (.*)/
  
  def execute(m, args)
    m.user.refresh
    if shared[:admins].include?(m.user.authname)
      args = args.scan(/\w+/)
      case args[0]
        when 'join'
          unless args[1].nil?
            args.delete('join')
            args.each do |person|
              r = shared[:game].register(person)
              if r.code == :confirmplayer
                Channel(bot.config.plugins.options[TWG::IRC]["game_channel"]).voice(person)
              end
            end
          end
        when 'vote'
          if !args[1].nil? && !args[2].nil?
            if shared[:game].state == :day
              r = shared[:game].vote(args[1], args[2], :channel)
            elsif shared[:game].state == :night
              r = shared[:game].vote(args[1], args[2], :private)
            end
            unless r.nil?
              m.reply "DEBUG: #{r.message}"
            end
          end
        when 'game'
          m.reply shared[:game].inspect
        when 'list'
          m.reply Channel(bot.config.plugins.options[TWG::IRC]["game_channel"]).users.inspect
        when 'authname'
          m.reply User(args[1]).authname unless args[1].nil?
      end
    end
  end
end