# encoding: utf-8
require 'cinch'
require 'twg/game'
require 'twg/helpers'
module TWG
  class Core
    include ::Cinch::Plugin
    include ::TWG::Helpers
    listen_to :enter_night, :method => :enter_night
    listen_to :enter_day, :method => :enter_day
    listen_to :exit_night, :method => :exit_night
    listen_to :exit_day, :method => :exit_day
    listen_to :ten_seconds_left, :method => :ten_seconds_left
    listen_to :warn_vote_timeout, :method => :warn_vote_timeout
    listen_to :complete_startup, :method => :complete_startup
    listen_to :hook_notify_roles, :method => :notify_roles
    listen_to :nick, :method => :nickchange
    listen_to :op, :method => :opped
    listen_to :deop, :method => :opped
    listen_to :do_allow_starts, :method => :do_allow_starts
    match "start", :method => :start
    match /vote ([^ ]+)(.*)?$/, :method => :vote
    match /abstain( .*)?$/, :method => :abstain
    match "votes", :method => :votes
    match "join", :method => :join
    match /join ([^ ]+)$/, :method => :forcejoin

    attr_accessor :game

    def initialize(*args)
      super
      @game = TWG::Game.new
      shared[:game] = @game
      @timer = nil
      @allow_starts = false
      @authnames = {}
    end

    def authn(user)
      return true if not config["use_authname"]
      @authnames[user.to_s] == user.authname
    end

    def abstain(m, reason)
      return if @game.nil?
      return if not authn(m.user)
      return if not [:night, :day].include?(@game.state)
      return if @game.state == :night && m.channel?
      return if @game.state == :day && !m.channel?
      if @game.abstain(m.user.to_s) == true
        if @game.state == :night
          m.reply "You have taken the Überwald League of Temperance's black ribbon - werewolf company."
        else
          m.reply "#{m.user.nick} has voted not to lynch"
        end
      end
    end

    def vote(m, mfor, reason)
      return if @game.nil?
      return if not authn(m.user)
      r = @game.vote(m.user.to_s, mfor, (m.channel? ? :channel : :private))
      debug "Vote result: #{r.inspect}"

      if m.channel?

        case r[:code]
        when :confirmvote
          if r[:previous].nil? || r[:previous] == :abstain
            m.reply "#{m.user} voted for %s" % Format(:bold, mfor)
          else
            m.reply "%s %s their vote from %s to %s" % [
              m.user,
              Format(:bold, "changed"),
              r[:previous],
              Format(:bold, mfor)
            ]
          end
        when :voteenotplayer
          m.reply "#{mfor} is not a player in this game", true
        when :voteedead
          m.reply "Good news #{m.user}, #{mfor} is already dead! "
        end

      else

        case r[:code]
        when :confirmvote
          if r[:previous].nil?
            m.reply "You have voted for #{mfor} to be killed tonight"
          else
            m.reply "You have changed your vote to #{mfor}"
          end
        when :fellowwolf
          m.reply "You can't vote for one of your own kind!"
        when :voteenotplayer
          m.reply "#{mfor} is not a player in this game"
        when :dead
          m.reply "#{mfor} is already dead"
        when :self
          m.reply "Error ID - 10T"
        end

      end
    end

    def votes(m)
      return if !m.channel?
      return if @game.state != :day
      tiebreak = @game.apply_votes(false)
      defer = nil
      order = {}
      @game.votes.each do |votee,voters|
        next if votee == :abstain
        order[voters.count] ||= []
        order[voters.count] << votee_summary(votee, voters, tiebreak)
      end
      sorted = order.keys.sort { |x,y| y <=> x }
      sorted.each do |i|
        order[i].each do |s|
          m.reply s
        end
      end
      if @game.votes.keys.include?(:abstain)
        m.reply votee_summary(:abstain, @game.votes[:abstain], tiebreak)
      end
    end

    def votee_summary(votee, voters, tiebreak)
      if votee == :abstain
        message = "%d peaceful %s voted not to lynch (%s)." % [
          voters.count,
          voters.count > 1 ? "souls have" : "soul has",
          voters.join(', ')
        ]
      else
        message = "%s has %d %s (%s)." % [
          votee,
          voters.count,
          voters.count > 1 ? "votes" : "vote",
          voters.join(', ')
        ]
      end
      message = Format(:italic, message) if tiebreak.include?(votee)
      return message
    end

    def opped(m, *args)
      @isopped ||= false
      chan, mode, user = m.params
      @game = TWG::Game.new if @game.nil?
      if chan == config["game_channel"] && mode == "+o" && user == bot.nick
        @isopped = true
        unless [:night,:day].include?(@game.state) || @signup_started == true
          wipe_slate
          hook_async(:do_allow_starts, 15)
        end
      elsif chan == config["game_channel"] && mode == "-o" && user == bot.nick
        chanm Format(:bold, "Cancelling game! I have been deopped!") if @game.state != :signup || (@game.state == :signup && @signup_started == true)
        @game = nil
        @signup_started = false
        @isopped = false
        @allow_starts = false
      end
    end

    def do_allow_starts(m)
      chanm "TWG bot is now up and running! Say !start to start a new game."
      @allow_starts = true
    end

    def nickchange(m)
      oldname = m.user.last_nick.to_s
      newname = m.user.to_s
      return if @game.nil?
      return if @game.participants[oldname].nil?
      return if @game.participants[oldname] == :dead
      if not @authnames.delete(oldname).nil?
        @game.nickchange(oldname, newname)
        @authnames[newname] = m.user.authname
        chanm("Player %s is now known as %s" % [Format(:bold, m.user.last_nick), Format(:bold, m.user.to_s)])
      end
    end

    def start(m)
      return if !m.channel?
      return if m.channel != config["game_channel"]
      if !@allow_starts
        if @isopped
          m.reply "I'm not ready yet, #{m.user.to_s}. Give me a few seconds."
        else
          m.reply "I require channel ops before starting a game"
        end 
        return
      end
      if @game.nil?
        @game = TWG::Game.new
      else
        if @signup_started == true
          hook_cancel(:ten_seconds_left)
          hook_expedite(:complete_startup)
          return
        end
      end
      if @game.state.nil? || @game.state == :wolveswin || @game.state == :humanswin
        @game.reset
      end
      if @game.state == :signup
        unless m.user.authname.nil?
          wipe_slate
          @signup_started = true
          m.reply "TWG has been started by #{m.user}!"
          m.reply "Registration is now open, say !join to join the game within #{config["game_timers"]["registration"]} seconds, !help for more information. A minimum of #{@game.min_part} players is required to play TWG."
          m.reply "Say !start again to skip the wait when everybody has joined"
          @game.register(m.user.to_s)
          voice(m.user)
          @authnames[m.user.to_s] = m.user.authname
          hook_async(:ten_seconds_left, config["game_timers"]["registration"] - 10)
          hook_async(:complete_startup, config["game_timers"]["registration"])
        else
          m.reply "you are unable to start a game as you are not authenticated to network services", true
        end
      end
    end

    def complete_startup(m)
      return if @game.nil?
      return unless @game.state == :signup
      r = @game.start
      @signup_started = false

      if r.code == :gamestart
        chanm "%s Players are: %s" % [Format(:bold, "Game starting!"), @game.participants.keys.sort.join(', ')]
        chanm "You will shortly receive your role via private message"
        Channel(config["game_channel"]).mode('+m')
        hook_sync(:hook_roles_assigned)
        hook_async(:hook_notify_roles)
        hook_async(:enter_night, 10)
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
      if !@game.nil? && @game.state == :signup
        r = @game.register(m.user.to_s)
        if r.code == :confirmplayer
          m.reply "#{m.user} has joined the game (#{@game.participants.length}/#{@game.min_part}[minimum])"
          Channel(config["game_channel"]).voice(m.user)
          @authnames[m.user.to_s] = m.user.authname
        end
      end
    end

    def forcejoin(m, user)
      return if not m.channel?
      return if not admin?(m.user)
      return if not @signup_started
      return if @game.nil?
      return if @game.state != :signup
      uobj = User(user)
      uobj.refresh
      if uobj.authname.nil?
        m.reply "Unable to add #{user} to the game - not identified with services", true
        return
      end
      r = @game.register(user)
      if r.code == :confirmplayer
        m.reply "#{user} has been forced to join the game (#{@game.participants.length}/#{@game.min_part}[minimum])"
        Channel(config["game_channel"]).voice(uobj)
        @authnames[user] = uobj.authname
      end
    end

    def ten_seconds_left(m)
      return if @game.nil?
      return unless @game.state == :signup
      chanm "10 seconds left to !join. #{@game.participants.length} out of a minimum of #{@game.min_part} players joined so far."
    end

    def warn_vote_timeout(m, secsremain)
      return if @game.nil?
      if @game.state == :day
        elligible = players_of_role(:dead, true)
        @game.votes.each do |votee, voted|
          voted.each do |voter|
            elligible.delete(voter)
          end
        end
        wmessage = Format(:bold, "Voting closes in #{secsremain} seconds! ")
        if elligible.count > 0
          wmessage << "Yet to vote: #{elligible.join(', ')}"
        else
          wmessage << "Everybody has voted, but it's not too late to change your mind..." 
        end
        chanm(wmessage)
      end
    end

    def enter_night(m)
      return if @game.nil?
      chanm("A chilly mist descends, %s #{@game.iteration}. Villagers, sleep soundly. Wolves, you have #{config["game_timers"]["night"]} seconds to decide who to rip to shreds." % Format(:underline, "it is now NIGHT"))
      @game.state_transition_in
      solicit_wolf_votes
      hook_async(:exit_night, config["game_timers"]["night"])
    end

    def exit_night(m)
      return if @game.nil?
      r = @game.apply_votes
      hook_sync(:hook_votes_applied)
      @game.next_state
      killed = nil
      if r.nil? || r == :abstain
        chanm("Everybody wakes, bleary eyed. %s Nobody was murdered during the night!" % Format(:underline, "There doesn't appear to be a body!"))
      else
        killed = r[0]
        chanm("A bloodcurdling scream is heard throughout the village. Everybody rushes to find the broken body of %s lying on the ground. %s, a villager, is dead." % [
              killed,
              Format(:red, killed)
        ])
        devoice(killed)
      end
      unless check_victory_conditions
        hook_async(:enter_day, 0, nil, killed)
      end
    end

    def enter_day(m,killed)
      return if @game.nil?
      @game.state_transition_in
      solicit_human_votes(killed)
      warn_timeout = config["game_timers"]["day_warn"]
      warn_timeout = [warn_timeout] if warn_timeout.class != Array
      warn_timeout.each do |warnat|
        secsremain = config["game_timers"]["day"].to_i - warnat.to_i
        hook_async(:warn_vote_timeout, secsremain, m, warnat.to_i)
      end
      hook_async(:exit_day, config["game_timers"]["day"])
    end

    def exit_day(m)
      return if @game.nil?
      r = @game.apply_votes
      hook_sync(:hook_votes_applied)
      @game.next_state
      k = nil
      role = nil
      if r.nil?
        chanm("Voting over! No votes were cast.")
      elsif r == :abstain
        chanm("Voting over! The villagers voted for peace... ლ(ಠ益ಠლ) But at what cost?")
      elsif r.class == Array
        k = r[0]
        role = r[1]
        chanm("Voting over! The baying mob has spoken - %s must die!" % Format(:bold, k))
        sleep 2
        chanm("Everybody turns slowly towards #{k}, who backs into a corner. With a quick flurry of pitchforks #{k} is no more. The villagers examine the body...")
        sleep(config["game_timers"]["dramatic_effect"])
      end
      if role == :wolf
        chanm("...and it starts to transform before their very eyes! A dead wolf lies before them.")
        devoice(k)
      elsif r != :abstain
        chanm("...but can't see anything unusual, looks like you might have turned upon one of your own.")
        devoice(k)
      end
      unless check_victory_conditions
        hook_async(:enter_night)
      end
    end

    def notify_roles(m)
      return if @game.nil?
      @game.participants.keys.each do |user|
        case @game.participants[user]
        when :normal
          userm(user, "You are a normal human being.")
        when :wolf
          if user == "michal"
            userm(user, "Holy shit you're finally a WOLF!")
          else
            userm(user, "You are a WOLF!")
          end
          wolfcp = @game.game_wolves.dup
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

    def admin?(user)
      user.refresh
      shared[:admins].include?(user.authname)
    end

    def check_victory_conditions
      return if @game.nil?
      if @game.state == :wolveswin
        if @game.live_wolves > 1
          chanm "With a bloodcurdling howl, hair begins sprouting from every orifice of the #{@game.live_wolves} triumphant wolves. The remaining villagers don't stand a chance." 
        else
          chanm("With a bloodcurdling howl, hair begins sprouting from %s's every orifice. The remaining villagers don't stand a chance." % Format(:bold, @game.wolves_alive[0]))
        end
        if @game.game_wolves.length == 1
          chanm("Game over! The lone wolf %s wins!" % Format(:bold, @game.wolves_alive[0]))
        else
          if @game.live_wolves == @game.game_wolves.length
            chanm("Game over! The wolves (%s) win!" % Format(:bold, @game.game_wolves.join(', ')))
          elsif @game.live_wolves > 1
            chanm("Game over! The remaining wolves (%s) win!" % Format(:bold, @game.wolves_alive.join(', ')))
          else
            chanm("Game over! The last remaining wolf, %s, wins!" % Format(:bold, @game.wolves_alive[0]))
          end
        end
        wipe_slate
        return true
      elsif @game.state == :humanswin
        if @game.game_wolves.length > 1
          chanm("Game over! The wolves (%s) were unable to pull the wool over the humans' eyes." % Format(:bold, @game.game_wolves.join(', ')))
        else
          chanm("Game over! The lone wolf %s was unable to pull the wool over the humans' eyes." % Format(:bold, @game.game_wolves[0]))
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
      return if @game.nil?
      if @game.state == :night
        solicit_wolf_votes
      elsif @game.state == :day
        solicit_human_votes
      end
    end

    def solicit_wolf_votes
      return if @game.nil?
      alive = @game.wolves_alive
      if alive.length == 1
        if @game.game_wolves.length == 1
          whatwereyou = "You are a lone wolf."
        else
          whatwereyou = "You are the last remaining wolf."
        end
        userm(alive[0], "It is now NIGHT #{@game.iteration}: #{whatwereyou} To choose the object of your bloodlust, say !vote <nickname> to me. You can !vote again if you change your mind.")
        return
      elsif alive.length == 2
        others = "Talk with your fellow wolf"
      else
        others = "Talk with your fellow wolves to decide who to kill"
      end
      alive.each do |wolf|
        userm(wolf, "It is now NIGHT #{@game.iteration}: To choose the object of your bloodlust, say !vote <nickname> to me. You can !vote again if you change your mind. #{others}") 
      end
    end

    def solicit_human_votes(killed=nil)
      return if @game.nil?
      if killed.nil?
        blurb = "Talk to your fellow villagers about this unusual and eery lupine silence!"
      else
        blurb = "Talk to your fellow villagers about #{killed}'s untimely demise!"
      end
      chanm("It is now DAY #{@game.iteration}: #{blurb} You have #{config["game_timers"]["day"]} seconds to vote on who to lynch by saying !vote nickname. If you change your mind, !vote again.")
    end

    def chanm(m)
      Channel(config["game_channel"]).send(m)
    end

    def userm(user, m)
      User(user).send(m)
    end

    def wipe_slate
      @game.reset
      @signup_started = false
      @timer = nil
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
