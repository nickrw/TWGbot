require 'twg/game'
module TWG
  class IRC
    include Cinch::Plugin
    listen_to :enter_night, :method => :enter_night
    listen_to :enter_day, :method => :enter_day
    listen_to :exit_night, :method => :exit_night
    listen_to :exit_day, :method => :exit_day
    listen_to :ten_seconds_left, :method => :ten_seconds_left
    listen_to :warn_vote_timeout, :method => :warn_vote_timeout
    listen_to :complete_startup, :method => :complete_startup
    listen_to :notify_roles, :method => :notify_roles
    listen_to :nick, :method => :nickchange
    listen_to :op, :method => :opped
    listen_to :deop, :method => :opped
    listen_to :do_allow_starts, :method => :do_allow_starts
    match "start", :method => :start
    match /vote ([^ ]+)(.*)?$/, :method => :vote
    match "votes", :method => :votes
    match "join", :method => :join
      
    def initialize(*args)
      super
      shared[:game] = TWG::Game.new if shared[:game].nil?
      @allow_starts = false
      @authnames = {}
    end

    def vote(m, mfor, reason)
      unless shared[:game].nil?
        m.user.refresh
        return if @authnames[m.user.to_s] != m.user.authname
        r = shared[:game].vote(m.user.to_s, mfor, (m.channel? ? :channel : :private))
        if r.code == :confirmvote
          if m.channel?
            rmessage = "#{m.user} voted for %s" % Format(:bold, mfor)
          else
            rmessage = "You have voted for #{mfor} to be uglied to death tonight"
          end
          m.reply rmessage
        elsif r.code == :changedvote
          if m.channel?
            rmessage = "#{m.user} %s their vote to %s" % [Format(:bold, "changed"), Format(:bold, mfor)]
          else
            rmessage = "You have changed your vote to #{mfor}"
          end
          m.reply rmessage
        end
      end
    end
    
    def votes(m)
      return if !m.channel?
      return if shared[:game].state != :day
      tally = {}
      shared[:game].voted.each do |voter,votee|
        if tally[votee]
          tally[votee] << voter
        else
          tally[votee] = [voter]
        end
      end
      tally.each do |votee,voters|
        chanm "#{votee} has #{voters.count} vote#{voters.count > 1 ? "s" : nil} (#{voters.join(', ')})."
      end
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
          delaydispatch(15, :do_allow_starts)
        end
      elsif chan == config["game_channel"] && mode == "-o" && user == bot.nick
        chanm Format(:bold, "Cancelling game! I have been deopped!") if shared[:game].state != :signup || (shared[:game].state == :signup && @signup_started == true)
        shared[:game] = nil
        @signup_started = false
        @isopped = false
        @allow_starts = false
      end
    end

    def do_allow_starts(m)
      chanm "TUDG bot is now up and running! Say !start to start a new game."
      @allow_starts = true
    end

    def nickchange(m)
      unless shared[:game].nil?
        if shared[:game].state != :signup && shared[:game].participants[m.user.to_s] && shared[:game].participants[m.user.to_s] != :dead
          shared[:game].nickchange(m.user.last_nick, m.user.to_s)
          @authnames[m.user.to_s] = @authnames.delete(m.user.last_nick)
          chanm("Player %s is now known as %s" % [Format(:bold, m.user.last_nick), Format(:bold, m.user.to_s)])
        end
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
        unless m.user.authname.nil?
          wipe_slate
          @signup_started = true
          m.reply "TUDG has been started by #{m.user}!"
          m.reply "Registration is now open, say !join to join the game within #{config["game_timers"]["registration"]} seconds, !help for more information. A minimum of #{shared[:game].min_part} players is required to play TUDG."
          shared[:game].register(m.user.to_s)
          voice(m.user)
          @authnames[m.user.to_s] = m.user.authname
          delaydispatch(config["game_timers"]["registration"] - 10, :ten_seconds_left, m)
          delaydispatch(config["game_timers"]["registration"], :complete_startup, m)
        else
          m.reply "you are unable to start a game as you are not authenticated to network services", true
        end
      end
    end

    def complete_startup(m)
      return if shared[:game].nil?
      return unless shared[:game].state == :signup
      r = shared[:game].start

      if r.code == :gamestart
        chanm "%s Players are: %s" % [Format(:bold, "Game starting!"), shared[:game].participants.keys.sort.join(', ')]
        chanm "You will shortly receive your role via private message"
        Channel(config["game_channel"]).mode('+m')
        bot.handlers.dispatch(:notify_roles)
        delaydispatch(10, :enter_night)
      elsif r.code == :notenoughplayers
        chanm "Not enough players to start a game, sorry guys. You can !start another if you find more players."
        wipe_slate
      else
        chanm Format(:red, "An unexpected error occured, the game could not be started.")
        wipe_slate
      end
    end
    
    def join(m)
      return if !m.channel?
      return if !@signup_started
      if m.user.authname.nil?
        m.reply "unable to add you to the game, you are not identified with services", true
        return
      end
      if !shared[:game].nil? && shared[:game].state == :signup
        r = shared[:game].register(m.user.to_s)
        if r.code == :confirmplayer
          m.reply "#{m.user} has joined the game (#{shared[:game].participants.length}/#{shared[:game].min_part}[minimum])"
          Channel(config["game_channel"]).voice(m.user)
          @authnames[m.user.to_s] = m.user.authname
        end
      end
    end

    def ten_seconds_left(m)
      return if shared[:game].nil?
      return unless shared[:game].state == :signup
      chanm "10 seconds left to !join. #{shared[:game].participants.length} out of a minimum of #{shared[:game].min_part} players joined so far."
    end

    def warn_vote_timeout(m, secsremain)
      return if shared[:game].nil?
      if shared[:game].state == :day
        notvoted = []
        shared[:game].participants.each do |player,state|
          next if state == :dead
          unless shared[:game].voted.keys.include?(player)
            notvoted << player
          end
        end
        wmessage = Format(:bold, "Voting closes in #{secsremain} seconds! ")
        if notvoted.count > 0
          wmessage << "Yet to vote: #{notvoted.join(', ')}"
        else
          wmessage << "Everybody has voted, but it's not too late to change your mind..." 
        end
        chanm(wmessage)
      end
    end

    def enter_night(m)
      return if shared[:game].nil?
      chanm("Somebody mistakenly presses for applause, %s #{shared[:game].iteration}. Mendeleyans, sleep soundly. Ugly dogs, you have #{config["game_timers"]["night"]} seconds to decide who to slobber on." % Format(:underline, "it is now NIGHT"))
      shared[:game].state_transition_in
      solicit_wolf_votes 
      delaydispatch(config["game_timers"]["night"], :exit_night, m)
    end
  
    def exit_night(m)
      return if shared[:game].nil?
      r = shared[:game].next_state
      bot.handlers.dispatch(:seer_reveal, m, shared[:game].reveal)
      if r.code == :normkilled
        k = r.opts[:killed]
        chanm("A bloodcurdling squeal is heard throughout the office. Everybody rushes to find the broken body of #{k} lying in an ugly pool of drool. Their body bears the unmistakable signs of being looked at by an ugly dog. %s" % Format(:red, "#{k.capitalize}, a mendeleyan, is dead."))
        devoice(k)
      elsif r.code == :novotes
        k = :none
        chanm("Everybody wakes, bleary eyed. %s Nobody was murdered during the night!" % Format(:underline, "There doesn't appear to be a body!"))
      end
      unless check_victory_conditions
        bot.handlers.dispatch(:enter_day, m, k)
      end
    end

    def enter_day(m,killed)
      return if shared[:game].nil?
      shared[:game].state_transition_in
      solicit_human_votes(killed)
      warn_timeout = config["game_timers"]["day_warn"]
      warn_timeout = [warn_timeout] if warn_timeout.class != Array
      warn_timeout.each do |warnat|
        secsremain = config["game_timers"]["day"].to_i - warnat.to_i
        delaydispatch(secsremain, :warn_vote_timeout, m, warnat.to_i)
      end
      delaydispatch(config["game_timers"]["day"], :exit_day, m)
    end

    def exit_day(m)
      return if shared[:game].nil?
      r = shared[:game].next_state
      k = r.opts[:killed]
      unless r.code == :novotes
        chanm "Voting over! The baying mob has spoken - %s must die!" % Format(:bold, k)
        sleep 2
        chanm("Everybody turns slowly towards #{k}, who backs into a corner. With a quick flurry of pitchforks #{k} is no more. The dilligent workers examine the body...")
        sleep(config["game_timers"]["dramatic_effect"])
      else
        chanm("Voting over! No consensus could be reached.")
      end
      if r.code == :normkilled
        chanm("...but can't see anything unusual, looks like you might have turned upon one of your own.")
        devoice(k)
      elsif r.code == :wolfkilled
        chanm("...and it starts to transform before their very eyes! A hideous puppy lies before them.")
        devoice(k)
      end
      unless check_victory_conditions
        bot.handlers.dispatch(:enter_night,m)
      end
    end

    def notify_roles(m)
      return if shared[:game].nil?
      shared[:game].participants.keys.each do |user|
        case shared[:game].participants[user]
        when :normal
          userm(user, "You are a normal mendeleyan.")
        when :wolf
          userm(user, "You are an UGLY DOG!")
          wolfcp = shared[:game].game_wolves.dup
          wolfcp.delete(user)
          if wolfcp.length > 1
            userm(user, "Your fellow ugly dogs are: #{wolfcp.join(', ')}")
          elsif wolfcp.length == 1
            userm(user, "Your fellow ugly dog is: #{wolfcp[0]}")
          elsif wolfcp.length == 0
            userm(user, "You are the only ugly dog in this game.")
          end
        end
      end
    end

    private
    
    def admin?(user)
      user.refresh
      shared[:admins].include?(user.authname)
    end

    def delaydispatch(secs, method, m = nil, *args)
      Timer(secs, {:shots => 1}) do
        bot.handlers.dispatch(method, m, *args)
      end
    end

    def check_victory_conditions
      return if shared[:game].nil?
      if shared[:game].state == :wolveswin
        if shared[:game].live_wolves > 1
          chanm "With a sickening gutteral noise due to centuries of inbreeding, slobber begins dripping from the corners of the #{shared[:game].live_wolves} triumphant ugly dogs' mouthes. The remaining mendeleyans don't stand a chance." 
        else
          chanm "With a sickening gutteral noise due to centuries of inbreeding, slobber begins dripping from #{shared[:game].wolves_alive[0]}'s mouth. The remaining mendeleyans don't stand a chance."
        end
        if shared[:game].game_wolves.length == 1
          chanm "Game over! The lone ugly dog #{shared[:game].wolves_alive[0]} wins!"
        else
          if shared[:game].live_wolves == shared[:game].game_wolves.length
            chanm "Game over! The ugly dogs (#{shared[:game].game_wolves.join(', ')}) win!"
          elsif shared[:game].live_wolves > 1
            chanm "Game over! The remaining ugly dog (#{shared[:game].wolves_alive.join(', ')}) win!"
          else
            chanm "Game over! The last remaining ugly dog, #{shared[:game].wolves_alive[0]}, wins!"
          end
        end
        wipe_slate
        return true
      elsif shared[:game].state == :humanswin
        if shared[:game].game_wolves.length > 1
          chanm "Game over! The ugly dogs (#{shared[:game].game_wolves.join(', ')}) was unable to outrun the mendeleyans on their pitiful legs."
        else
          chanm "Game over! The ugly dog #{shared[:game].game_wolves[0]} was unable to outrun the mendeleyans on its pitiful legs."
        end
        wipe_slate
        return true
      else
        return false
      end
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
          whatwereyou = "You are a lonesome ugly dog."
        else
          whatwereyou = "You are the last remaining ugly dog."
        end
        userm(alive[0], "It is now NIGHT #{shared[:game].iteration}: #{whatwereyou} To choose who to slobber over, say !vote <nickname> to me. You can !vote again if you change your mind.")
        return
      elsif alive.length == 2
        others = "Talk with your fellow ugly dog"
      else
        others = "Talk with your fellow ugly dog to decide who to kill"
      end
      alive.each do |wolf|
        userm(wolf, "It is now NIGHT #{shared[:game].iteration}: To choose who to slobber over, say !vote <nickname> to me. You can !vote again if you change your mind. #{others}") 
      end
    end

    def solicit_human_votes(killed=:none)
      return if shared[:game].nil?
      if killed == :none
        blurb = "Have a stand-up with your colleagues to talk about this unusual and eery dog absence!"
      else
        blurb = "Schedule an urgent meeting with your colleagues about #{killed}'s untimely demise!"
      end
      chanm("It is now DAY #{shared[:game].iteration}: #{blurb} You have #{config["game_timers"]["day"]} seconds to vote on who to lynch by saying !vote nickname. If you change your mind, !vote again.")
    end

    def chanm(m)
      Channel(config["game_channel"]).send(m)
    end

    def userm(user, m)
      User(user).send(m)
    end

    def wipe_slate
      @signup_started = false
      @gchan = Channel(config["game_channel"])
      @authnames = {}
      @gchan.mode('-m')
      deop = []
      devoice = []
      @gchan.users.each do |user,mode|
        next if user == bot.nick
        deop << user if mode.include? 'o'
        devoice << user if mode.include? 'v'
      end
      multimode(deop, config["game_channel"], "-", "o")
      multimode(devoice, config["game_channel"], "-", "v")
    end

    def multimode(musers, mchannel, direction, mode)
      while musers.count > 0
        if musers.count < 4
          rc = musers.count
        else
          rc = 4
        end
        add = musers.pop(rc)
        ms = direction + mode * rc
        bot.irc.send "MODE %s %s %s" % [mchannel, ms, add.join(" ")]
      end
    end

  end

end
