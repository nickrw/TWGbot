require File.expand_path(File.dirname(__FILE__)) + '/core'
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
      unless @bot.config.game.nil?
        r = @bot.config.game.vote(m.user.to_s, mfor, (m.channel? ? :channel : :private))
        if r.code == :confirmvote
          if m.channel?
            rmessage = "#{m.user} voted for #{mfor}"
          else
            rmessage = "You have voted for #{mfor} to be killed tonight"
          end
          m.reply rmessage
        end
      end
    end
    
    def initialize(*args)
      super
      @bot.config.game = TWG::Game.new if @bot.config.game.nil?
      @bot.config.allow_starts = false
    end

    def opped(m, *args)
      @isopped ||= false
      @bot.loggers.debug "Opped params: %s" % m.params.inspect 
      chan, mode, user = m.params
      @bot.config.game = TWG::Game.new if @bot.config.game.nil?
      if chan == @bot.config.game_channel && mode == "+o" && user == @bot.nick
        @isopped = true
        unless [:night,:day].include?(@bot.config.game.state) || @signup_started == true
          wipe_slate
          chanm "TWG bot is now up and running! Say !start to start a new game."
        end
        @bot.config.allow_starts = true
      elsif chan == @bot.config.game_channel && mode == "-o" && user == @bot.nick
        chanm "Cancelling game! I have been deopped!" if @bot.config.game.state != :signup || (@bot.config.game.state == :signup && @signup_started == true)
        @bot.config.game = nil
        @signup_started = false
        @isopped = false
        @bot.config.allow_starts = false
      end
    end

    def wipe_slate
      @signup_started = false
      gchan = Channel(@bot.config.game_channel)
      gchan.mode('-m')
      gchan.users.each do |user,mode|
        devoice(user) if mode.include? 'v'
      end
    end

    def nickchange(m)
      unless @bot.config.game.nil?
        @bot.config.game.nickchange(m.user.last_nick, m.user.nick)
        chanm("Player %s is now known as %s" % [m.user.last_nick, m.user.nick]) if @bot.config.game.participants[m.user.nick] != :dead
      end
    end

    def start(m)
      return if !m.channel?
      return if m.channel != @bot.config.game_channel
      if !@bot.config.allow_starts
      m.reply "I require channel ops before starting a game"
      return
      end
      if @bot.config.game.nil?
        @bot.config.game = TWG::Game.new
      else
        return if @signup_started == true
      end
      if @bot.config.game.state.nil? || @bot.config.game.state == :wolveswin || @bot.config.game.state == :humanswin
        @bot.config.game.reset
      end
      if @bot.config.game.state == :signup
        wipe_slate
        @signup_started = true
        m.reply "TWG has been started by #{m.user}!"
        m.reply "Registration is now open, say !join to join the game within #{@bot.config.game_timers[:registration]} seconds, !help for more information. A minimum of #{@bot.config.game.min_part} players is required to play TWG."
        @bot.config.game.register(m.user.to_s)
        voice(m.user)
        @bot.handlers.dispatch(:ten_seconds_left, m)
        @bot.handlers.dispatch(:complete_startup, m)
      end
    end

    def complete_startup(m)
      sleep(@bot.config.game_timers[:registration])
      return if @bot.config.game.nil?
      return unless @bot.config.game.state == :signup
      r = @bot.config.game.start

      if r.code == :gamestart
        chanm "Game starting! Players are: #{@bot.config.game.participants.keys.sort.join(', ')}"
        chanm "You will shortly receive your role via private message"
        #@bot.config.game.participants.keys.sort.each { |part| voice(part) }
        Channel(@bot.config.game_channel).mode('+m')
        @bot.handlers.dispatch(:notify_roles)
        sleep 5
        @bot.handlers.dispatch(:enter_night)
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
      if !@bot.config.game.nil? && @bot.config.game.state == :signup
        r = @bot.config.game.register(m.user.to_s)
        if r.code == :confirmplayer
          m.reply "#{m.user} has joined the game (#{@bot.config.game.participants.length}/#{@bot.config.game.min_part}[minimum])"
          Channel(@bot.config.game_channel).voice(m.user)
        end
      end
    end

    def ten_seconds_left(m)
      sleep(@bot.config.game_timers[:registration] - 10)
      return if @bot.config.game.nil?
      return unless @bot.config.game.state == :signup
      chanm "10 seconds left to !join. #{@bot.config.game.participants.length} out of a minimum of #{@bot.config.game.min_part} players joined so far."
    end

    def enter_night(m)
      return if @bot.config.game.nil?
      chanm("A chilly mist decends, it is now NIGHT #{@bot.config.game.iteration}. Villagers, sleep soundly. Wolves, you have #{@bot.config.game_timers[:night]} seconds to decide who to rip to shreds.")
      @bot.config.game.state_transition_in
      solicit_wolf_votes 
      sleep @bot.config.game_timers[:night]
      @bot.handlers.dispatch(:exit_night, m)
    end
  
    def exit_night(m)
      return if @bot.config.game.nil?
      r = @bot.config.game.next_state
      @bot.handlers.dispatch(:seer_reveal, m, @bot.config.game.reveal)
      if r.code == :normkilled
        k = r.opts[:killed]
        chanm("A bloodcurdling scream is heard throughout the village. Everybody rushes to find the broken body of #{k} lying on the ground. #{k}, a villager, is dead.")
        devoice(k)
      elsif r.code == :novotes
        k = :none
        chanm("Everybody wakes, bleary eyed. There doesn't appear to be any body! Nobody was murdered during the night!")
      end
      unless check_victory_conditions
        @bot.handlers.dispatch(:enter_day, m, k)
      end
    end

    def enter_day(m,killed)
      return if @bot.config.game.nil?
      @bot.config.game.state_transition_in
      solicit_human_votes(killed)
      sleep @bot.config.game_timers[:day]
      @bot.handlers.dispatch(:exit_day,m)
    end

    def exit_day(m)
      return if @bot.config.game.nil?
      r = @bot.config.game.next_state
      chanm "Voting over!"
      if r.code == :normkilled
        k = r.opts[:killed]
        chanm("Everybody turns slowly towards #{k}, who backs into a corner. With a quick flurry of pitchforks #{k} is no more. The villagers examine the body...")
        sleep(@bot.config.game_timers[:dramatic_effect])
        chanm("...but can't see anything unusual, looks like you might have turned upon one of your own.")
        devoice(k)
      elsif r.code == :wolfkilled
        k = r.opts[:killed]
        chanm("Everybody turns slowly towards #{k}, who backs into a corner. With a quick flurry of pitchforks #{k} is no more. The villagers examine the body...")
        sleep(@bot.config.game_timers[:dramatic_effect])
        chanm("...and it starts to transform before their very eyes! A dead wolf lies before them.")
        devoice(k)
      else
        chanm("No consensus could be reached, hurrying off to bed the villagers uneasily hope that the wolves have already had their fill.")
      end
      unless check_victory_conditions
        @bot.handlers.dispatch(:enter_night,m)
      end
    end

    def check_victory_conditions
      return if @bot.config.game.nil?
      if @bot.config.game.state == :wolveswin
        if @bot.config.game.live_wolves > 1
          chanm "With a bloodcurdling howl, hair begins sprouting from every orifice of the #{@bot.config.game.live_wolves} triumphant wolves. The remaining villagers don't stand a chance." 
        else
          chanm "With a bloodcurdling howl, hair begins sprouting from #{@bot.config.game.wolves_alive[0]}'s every orifice. One human doesn't stand a chance."
        end
        if @bot.config.game.game_wolves.length == 1
          chanm "Game over! The lone wolf #{@bot.config.game.wolves_alive[0]} wins!"
        else
          if @bot.config.game.live_wolves == @bot.config.game.game_wolves.length
            chanm "Game over! The wolves (#{@bot.config.game.game_wolves.join(', ')}) win!"
          elsif @bot.config.game.live_wolves > 1
            chanm "Game over! The remaining wolves (#{@bot.config.game.wolves_alive.join(', ')}) win!"
          else
            chanm "Game over! The last remaining wolf, #{@bot.config.game.wolves_alive[0]}, wins!"
          end
        end
        wipe_slate
        return true
      elsif @bot.config.game.state == :humanswin
        if @bot.config.game.game_wolves.length > 1
          chanm "Game over! The wolves (#{@bot.config.game.game_wolves.join(', ')}) were unable to pull the wool over the humans' eyes."
        else
          chanm "Game over! The lone wolf #{@bot.config.game.game_wolves[0]} was unable to pull the wool over the humans' eyes."
        end
        wipe_slate
        return true
      else
        return false
      end
    end


    def notify_roles(m)
      return if @bot.config.game.nil?
      @bot.config.game.participants.keys.each do |user|
        case @bot.config.game.participants[user]
          when :normal
            userm(user, "You are a normal human being.")
          when :wolf
            userm(user, "You are a WOLF!")
            wolfcp = @bot.config.game.game_wolves.dup
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

    def devoice(uname)
      Channel(@bot.config.game_channel).devoice(uname)
    end

    def voice(uname)
      Channel(@bot.config.game_channel).voice(uname)
    end
    
    def solicit_votes
      return if @bot.config.game.nil?
      if @bot.config.game.state == :night
        solicit_wolf_votes
      elsif @bot.config.game.state == :day
        solicit_human_votes
      end
    end

    def solicit_wolf_votes
      return if @bot.config.game.nil?
      alive = @bot.config.game.wolves_alive
      if alive.length == 1
        if @bot.config.game.game_wolves.length == 1
          whatwereyou = "You are a lone wolf."
        else
          whatwereyou = "You are the last remaining wolf."
        end
        userm(alive[0], "It is now NIGHT #{@bot.config.game.iteration}: #{whatwereyou} To choose the object of your bloodlust, say !vote <nickname> to me. Choose carefully, you can only vote once.")
        return
      elsif alive.length == 2
        others = "Talk with your fellow wolf"
      else
        others = "Talk with your fellow wolves to decide who to kill"
      end
      alive.each do |wolf|
        userm(wolf, "It is now NIGHT #{@bot.config.game.iteration}: To choose the object of your bloodlust, say !vote <nickname> to me. Choose carefully, you can only vote once. #{others}") 
      end
    end

    def solicit_human_votes(killed=:none)
      return if @bot.config.game.nil?
      if killed == :none
        blurb = "Talk to your fellow villagers about this unusual and eery lupine silence!"
      else
        blurb = "Talk to your fellow villagers about #{killed}'s untimely demise!"
      end
      chanm("It is now DAY #{@bot.config.game.iteration}: #{blurb} Cast your vote on who to lynch by saying !vote nickname. Choose carefully, you can only vote once.")
    end

    def chanm(m)
      Channel(@bot.config.game_channel).send(m)
    end

    def userm(user, m)
      User(user).send(m)
    end

    class Seer
      include Cinch::Plugin
      listen_to :notify_roles, :method => :notify_roles
      listen_to :enter_night, :method => :solicit_seer_choice
      listen_to :seer_reveal, :method => :seer_reveal
      match /see ([^ ]+)$/, :method => :see
  
      def initialize(*args)
        super
        @bot.config.game.enable_seer = true
      end
  
      def solicit_seer_choice(m)
        return if @bot.config.game.nil?
        if @bot.config.game.seer && @bot.config.game.participants[@bot.config.game.seer] != :dead
          User(@bot.config.game.seer).send "It is now NIGHT %s: say !see <nickname> to me to reveal their role." % @bot.config.game.iteration.to_s
        end
      end
      
      def seer_reveal(m, r = nil)
        return if @bot.config.game.nil?
        unless r.nil?
          case r.code
            when :targetkilled
              User(@bot.config.game.seer).send "You have a vision of %s's body, twisted, broken and bloody. It looks like a wolf got there before you." % r.opts[:target]
            when :youkilled
              User(@bot.config.game.seer).send "While dreaming vividly about %s you get viciously torn to pieces. Looks like your magic 8 ball didn't see that one coming!" % r.opts[:target]
            when :sawwolf
              User(@bot.config.game.seer).send "You have a vivid dream about %s wearing a new fur coat. It looks like you've found a WOLF." % r.opts[:target]
            when :sawhuman
              User(@bot.config.game.seer).send "You have a dull dream about %s lying in bed, dreaming. It looks like %s is a fellow villager." % [r.opts[:target], r.opts[:target]]
          end
        end
      end
  
      def notify_roles(m)
        return if @bot.config.game.nil?
        User(@bot.config.game.seer).send "You are the SEER. Each night you can have the role of a player of your choice revealed." if @bot.config.game.seer
      end
  
      def see(m, target)
        if @bot.config.game && m.channel? == false
          r = @bot.config.game.see(m.user.nick, target)
          case r.code
            when :confirmsee
              m.reply "#{target}'s identity will be revealed to you as you wake."
            when :seerself
              m.reply "Surely you know what you are... try again."
            when :targetdead
              m.reply "#{target} is dead, try again."
            when :alreadyseen
              m.reply "You have already selected tonight's vision!"
          end
        end
      end
    end


    class Debug
      include Cinch::Plugin
      listen_to :channel
      match /debug (.*)/
  
      def execute(m, args)
        m.user.refresh
        if @bot.config.admins.include?(m.user.authname)
          args = args.scan(/\w+/)
          case args[0]
            when 'join'
              unless args[1].nil?
                args.delete('join')
                args.each do |person|
                  r = @bot.config.game.register(person)
                  if r.code == :confirmplayer
                    Channel(@bot.config.game_channel).voice(person)
                  end
                end
              end
            when 'vote'
              if !args[1].nil? && !args[2].nil?
                if @bot.config.game.state == :day
                  r = @bot.config.game.vote(args[1], args[2], :channel)
                elsif @bot.config.game.state == :night
                  r = @bot.config.game.vote(args[1], args[2], :private)
                end
                unless r.nil?
                  m.reply "DEBUG: #{r.message}"
                end
              end
            when 'game'
              m.reply @bot.config.game.inspect
            when 'list'
              m.reply Channel(@bot.config.game_channel).users.inspect
            when 'authname'
              m.reply User(args[1]).authname unless args[1].nil?
          end
        end
      end
    end

  end

end
