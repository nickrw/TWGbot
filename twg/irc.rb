require 'twg/game'
module TWG
  class IRC
    include Cinch::Plugin
    listen_to :enter_night, :method => :enter_night
    listen_to :enter_day, :method => :enter_day
    listen_to :exit_night, :method => :exit_night
    listen_to :exit_day, :method => :exit_day
    listen_to :ten_seconds_left, :method => :ten_seconds_left
    listen_to :complete_startup, :method => :complete_startup
    listen_to :notify_roles, :method => :notify_roles
    listen_to :nick, :method => :nickchange
    listen_to :op, :method => :opped
    listen_to :deop, :method => :opped
    match "start", :method => :start
    match /vote ([^ ]+)$/, :method => :vote
    match "join", :method => :join
      
    def vote(m, mfor)
      unless shared[:game].nil?
        m.user.refresh
        r = shared[:game].vote(m.user.to_s, mfor, (m.channel? ? :channel : :private))
        if r.code == :confirmvote
          if m.channel?
            rmessage = "#{m.user} voted for #{mfor}"
          else
            rmessage = "You have voted for #{mfor} to be killed tonight"
          end
          m.reply rmessage
        elsif r.code == :changedvote
          if m.channel?
            rmessage = "#{m.user} changed their vote to #{mfor}"
          else
            rmessage = "You have changed your vote to #{mfor}"
          end
          m.reply rmessage
        end
      end
    end
    
    def initialize(*args)
      super
      shared[:game] = TWG::Game.new if shared[:game].nil?
      @allow_starts = false
    end

    def opped(m, *args)
      @isopped ||= false
      debug "Opped params: %s" % m.params.inspect 
      chan, mode, user = m.params
      shared[:game] = TWG::Game.new if shared[:game].nil?
      if chan == config["game_channel"] && mode == "+o" && user == bot.nick
        @isopped = true
        unless [:night,:day].include?(shared[:game].state) || @signup_started == true
          wipe_slate
          chanm "TWG bot is now up and running! Say !start to start a new game."
        end
        @allow_starts = true
      elsif chan == config["game_channel"] && mode == "-o" && user == bot.nick
        chanm "Cancelling game! I have been deopped!" if shared[:game].state != :signup || (shared[:game].state == :signup && @signup_started == true)
        shared[:game] = nil
        @signup_started = false
        @isopped = false
        @allow_starts = false
      end
    end

    def wipe_slate
      @signup_started = false
      gchan = Channel(config["game_channel"])
      gchan.mode('-m')
      gchan.users.each do |user,mode|
        devoice(user) if mode.include? 'v'
      end
    end

    def nickchange(m)
      unless shared[:game].nil?
        shared[:game].nickchange(m.user.last_nick, m.user.nick)
        chanm("Player %s is now known as %s" % [m.user.last_nick, m.user.nick]) if shared[:game].participants[m.user.nick] != :dead
      end
    end

    def start(m)
      return if !m.channel?
      return if m.channel != config["game_channel"]
      if !@allow_starts
      m.reply "I require channel ops before starting a game"
      return
      end
      if shared[:game].nil?
        shared[:game] = TWG::Game.new
      else
        return if @signup_started == true
      end
      if shared[:game].state.nil? || shared[:game].state == :wolveswin || shared[:game].state == :humanswin
        shared[:game].reset
      end
      if shared[:game].state == :signup
        wipe_slate
        @signup_started = true
        m.reply "TWG has been started by #{m.user}!"
        m.reply "Registration is now open, say !join to join the game within #{config["game_timers"]["registration"]} seconds, !help for more information. A minimum of #{shared[:game].min_part} players is required to play TWG."
        shared[:game].register(m.user.to_s)
        voice(m.user)
        bot.handlers.dispatch(:ten_seconds_left, m)
        bot.handlers.dispatch(:complete_startup, m)
      end
    end

    def complete_startup(m)
      sleep(config["game_timers"]["registration"])
      return if shared[:game].nil?
      return unless shared[:game].state == :signup
      r = shared[:game].start

      if r.code == :gamestart
        chanm "Game starting! Players are: #{shared[:game].participants.keys.sort.join(', ')}"
        chanm "You will shortly receive your role via private message"
        #shared[:game].participants.keys.sort.each { |part| voice(part) }
        Channel(config["game_channel"]).mode('+m')
        bot.handlers.dispatch(:notify_roles)
        sleep 5
        bot.handlers.dispatch(:enter_night)
        #TODO: Register timer for first night
      elsif r.code == :notenoughplayers
        chanm "Not enough players to start a game, sorry guys. You can !start another if you find more players."
        wipe_slate
      else
        chanm "An unexpected error occured, the game could not be started."
        wipe_slate
      end
    end
    
    def join(m)
      return if !m.channel?
      return if !@signup_started
      if !shared[:game].nil? && shared[:game].state == :signup
        r = shared[:game].register(m.user.to_s)
        if r.code == :confirmplayer
          m.reply "#{m.user} has joined the game (#{shared[:game].participants.length}/#{shared[:game].min_part}[minimum])"
          Channel(config["game_channel"]).voice(m.user)
        end
      end
    end

    def ten_seconds_left(m)
      sleep(config["game_timers"]["registration"] - 10)
      return if shared[:game].nil?
      return unless shared[:game].state == :signup
      chanm "10 seconds left to !join. #{shared[:game].participants.length} out of a minimum of #{shared[:game].min_part} players joined so far."
    end

    def enter_night(m)
      return if shared[:game].nil?
      chanm("A chilly mist decends, it is now NIGHT #{shared[:game].iteration}. Villagers, sleep soundly. Wolves, you have #{config["game_timers"]["night"]} seconds to decide who to rip to shreds.")
      shared[:game].state_transition_in
      solicit_wolf_votes 
      sleep config["game_timers"]["night"]
      bot.handlers.dispatch(:exit_night, m)
    end
  
    def exit_night(m)
      return if shared[:game].nil?
      r = shared[:game].next_state
      bot.handlers.dispatch(:seer_reveal, m, shared[:game].reveal)
      if r.code == :normkilled
        k = r.opts[:killed]
        chanm("A bloodcurdling scream is heard throughout the village. Everybody rushes to find the broken body of #{k} lying on the ground. #{k}, a villager, is dead.")
        devoice(k)
      elsif r.code == :novotes
        k = :none
        chanm("Everybody wakes, bleary eyed. There doesn't appear to be any body! Nobody was murdered during the night!")
      end
      unless check_victory_conditions
        bot.handlers.dispatch(:enter_day, m, k)
      end
    end

    def enter_day(m,killed)
      return if shared[:game].nil?
      shared[:game].state_transition_in
      solicit_human_votes(killed)
      sleep config["game_timers"]["day"]
      bot.handlers.dispatch(:exit_day,m)
    end

    def exit_day(m)
      return if shared[:game].nil?
      r = shared[:game].next_state
      chanm "Voting over!"
      if r.code == :normkilled
        k = r.opts[:killed]
        chanm("Everybody turns slowly towards #{k}, who backs into a corner. With a quick flurry of pitchforks #{k} is no more. The villagers examine the body...")
        sleep(config["game_timers"]["dramatic_effect"])
        chanm("...but can't see anything unusual, looks like you might have turned upon one of your own.")
        devoice(k)
      elsif r.code == :wolfkilled
        k = r.opts[:killed]
        chanm("Everybody turns slowly towards #{k}, who backs into a corner. With a quick flurry of pitchforks #{k} is no more. The villagers examine the body...")
        sleep(config["game_timers"]["dramatic_effect"])
        chanm("...and it starts to transform before their very eyes! A dead wolf lies before them.")
        devoice(k)
      else
        chanm("No consensus could be reached, hurrying off to bed the villagers uneasily hope that the wolves have already had their fill.")
      end
      unless check_victory_conditions
        bot.handlers.dispatch(:enter_night,m)
      end
    end

    def check_victory_conditions
      return if shared[:game].nil?
      if shared[:game].state == :wolveswin
        if shared[:game].live_wolves > 1
          chanm "With a bloodcurdling howl, hair begins sprouting from every orifice of the #{shared[:game].live_wolves} triumphant wolves. The remaining villagers don't stand a chance." 
        else
          chanm "With a bloodcurdling howl, hair begins sprouting from #{shared[:game].wolves_alive[0]}'s every orifice. One human doesn't stand a chance."
        end
        if shared[:game].game_wolves.length == 1
          chanm "Game over! The lone wolf #{shared[:game].wolves_alive[0]} wins!"
        else
          if shared[:game].live_wolves == shared[:game].game_wolves.length
            chanm "Game over! The wolves (#{shared[:game].game_wolves.join(', ')}) win!"
          elsif shared[:game].live_wolves > 1
            chanm "Game over! The remaining wolves (#{shared[:game].wolves_alive.join(', ')}) win!"
          else
            chanm "Game over! The last remaining wolf, #{shared[:game].wolves_alive[0]}, wins!"
          end
        end
        wipe_slate
        return true
      elsif shared[:game].state == :humanswin
        if shared[:game].game_wolves.length > 1
          chanm "Game over! The wolves (#{shared[:game].game_wolves.join(', ')}) were unable to pull the wool over the humans' eyes."
        else
          chanm "Game over! The lone wolf #{shared[:game].game_wolves[0]} was unable to pull the wool over the humans' eyes."
        end
        wipe_slate
        return true
      else
        return false
      end
    end


    def notify_roles(m)
      return if shared[:game].nil?
      shared[:game].participants.keys.each do |user|
        case shared[:game].participants[user]
          when :normal
            userm(user, "You are a normal human being.")
          when :wolf
            userm(user, "You are a WOLF!")
            wolfcp = shared[:game].game_wolves.dup
            wolfcp.delete(user)
            if wolfcp.length > 1
              userm(user, "Your fellow wolves are: #{wolfcp.join(', ')}")
            elsif wolfcp.length == 1
              userm(user, "Your fellow wolf is: #{wolfcp[0]}")
            elsif wolfcp.length == 0
              userm(user, "You are the only wolf in this game.")
            end
        end
      end
    end

    private
    
    def admin?(user)
      user.refresh
      shared[:admins].include?(user.authname)
    end

    def devoice(uname)
      Channel(config["game_channel"]).devoice(uname)
    end

    def voice(uname)
      Channel(config["game_channel"]).voice(uname)
    end
    
    def solicit_votes
      return if shared[:game].nil?
      if shared[:game].state == :night
        solicit_wolf_votes
      elsif shared[:game].state == :day
        solicit_human_votes
      end
    end

    def solicit_wolf_votes
      return if shared[:game].nil?
      alive = shared[:game].wolves_alive
      if alive.length == 1
        if shared[:game].game_wolves.length == 1
          whatwereyou = "You are a lone wolf."
        else
          whatwereyou = "You are the last remaining wolf."
        end
        userm(alive[0], "It is now NIGHT #{shared[:game].iteration}: #{whatwereyou} To choose the object of your bloodlust, say !vote <nickname> to me. You can !vote again if you change your mind.")
        return
      elsif alive.length == 2
        others = "Talk with your fellow wolf"
      else
        others = "Talk with your fellow wolves to decide who to kill"
      end
      alive.each do |wolf|
        userm(wolf, "It is now NIGHT #{shared[:game].iteration}: To choose the object of your bloodlust, say !vote <nickname> to me. You can !vote again if you change your mind. #{others}") 
      end
    end

    def solicit_human_votes(killed=:none)
      return if shared[:game].nil?
      if killed == :none
        blurb = "Talk to your fellow villagers about this unusual and eery lupine silence!"
      else
        blurb = "Talk to your fellow villagers about #{killed}'s untimely demise!"
      end
      chanm("It is now DAY #{shared[:game].iteration}: #{blurb} Cast your vote on who to lynch by saying !vote nickname. If you change your mind, !vote again.")
    end

    def chanm(m)
      Channel(config["game_channel"]).send(m)
    end

    def userm(user, m)
      User(user).send(m)
    end

  end

end
