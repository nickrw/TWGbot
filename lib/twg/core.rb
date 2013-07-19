# encoding: utf-8
require 'cinch'
require 'twg/game'
require 'twg/helpers'
require 'twg/lang'
require 'twg/loader'
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
    listen_to :join, :method => :channel_join
    listen_to :op, :method => :opped
    listen_to :deop, :method => :opped
    listen_to :hook_allow_starts, :method => :allow_starts

    attr_accessor :lang
    attr_accessor :game
    attr_accessor :signup_started

    def initialize(*args)
      super
      @game = TWG::Game.new
      default_lang = config["default_lang"] ||= :default
      @@lang ||= default_lang
      @lang = TWG::Lang.new(@@lang)

      commands = {
        @lang.t('command.start') => :start,
        Regexp.new(@lang.t('command.vote') + " ([^ ]+)(.*)?$") => :vote,
        Regexp.new(@lang.t('command.abstain') + "( .*)?$") => :abstain,
        @lang.t('command.votes') => :votes,
        @lang.t('command.join') => :join,
        Regexp.new(@lang.t('command.join') + " ([^ ]+)$") => :forcejoin,
        @lang.t('command.langs') => :langlist,
        Regexp.new(@lang.t('command.lang') + " ([^ ]+)$") => :selectlang
      }

      commands.each do |pattern,method|
        self.class.match(pattern, :method => method)
      end
      __register_matchers

      shared[:game] = @game
      @timer = nil
      @allow_starts = false
      check_ready
    end

    def langlist(m)
      return if !m.channel?
      return if m.channel != config["game_channel"]
      return if not @allow_starts
      case @game.state
      when nil, :signup, :wolveswin, :humanswin
      else
        return
      end
      m.reply @lang.t 'lang.packs'
      @lang.list.each do |pack, desc|
        message = "#{pack}: #{desc}"
        if @lang.pack == pack
          message = Format(:italic, message)
        end
        m.reply message
      end
    end

    def selectlang(m, lang)
      return if !m.channel?
      return if m.channel != config["game_channel"]
      return if not @allow_starts
      case @game.state
      when nil, :signup, :wolveswin, :humanswin
      else
        return
      end
      r = @lang.select(lang.to_sym)
      if r.nil?
        m.reply @lang.t('lang.notfound', {:lang => lang})
      else
        @@lang = lang.to_sym
        i = bot.plugins.find_index { |x| x.class == TWG::Loader }
        if i.nil?
          bot.plugins.register_plugin(TWG::Loader)
        end
        hook_async(:hook_reload_all)
      end
    end

    def abstain(m, reason)
      return if @game.nil?
      return if not [:night, :day].include?(@game.state)
      return if @game.state == :night && m.channel?
      return if @game.state == :day && !m.channel?
      if @game.abstain(m.user.to_s) == true
        if @game.state == :night
          m.reply @lang.t('vote.night.abstain')
        else
          m.reply @lang.t('vote.day.abstain', {:voter => m.user.to_s})
        end
      end
    end

    def opped?
      begin
        ch = Channel(config["game_channel"])
      rescue NoMethodError
        return false
      end
      return false if ch.users.nil?
      return false if not ch.users.keys.include?(bot)
      ch.users[bot].include?('o')
    end

    def check_ready
      synchronize(:check_ready) do
        begin
          ch = Channel(config["game_channel"])
        rescue NoMethodError
          return
        end
        return if ch.users.nil?
        return if not ch.users.keys.include?(bot)
        return if not opped?
        return if @signup_started
        return if [:night,:day].include?(@game.state)
        wipe_slate
        hook_sync(:hook_allow_starts)
      end
    end

    def channel_join(m)
      if m.user.to_s == bot.nick
        check_ready
      else
        return if @game.nil?
        return if @game.participants[m.user.to_s].nil?
        return if @game.participants[m.user.to_s] == :dead
        voice(m.user)
      end
    end

    def vote(m, mfor, reason)
      return if @game.nil?
      r = @game.vote(m.user.to_s, mfor, (m.channel? ? :channel : :private))

      if m.channel?

        case r[:code]
        when :confirmvote
          if r[:previous].nil? || r[:previous] == :abstain
            m.reply @lang.t('vote.day.vote', {
              :voter => m.user.to_s,
              :votee => Format(:bold, mfor)
            })
          else
            m.reply @lang.t('vote.day.changed', {
              :voter     => m.user.to_s,
              :origvotee => r[:previous],
              :votee     => Format(:bold, mfor)
            })
          end
        when :voteenotplayer
          m.reply @lang.t('vote.noplayer', {:votee => mfor})
        when :voteedead
          m.reply @lang.t('vote.day.dead', {
            :voter => m.user.to_s,
            :votee => mfor
          })
        end

      else

        case r[:code]
        when :confirmvote
          if r[:previous].nil?
            m.reply @lang.t('vote.night.vote', {:votee => mfor})
          else
            m.reply @lang.t('vote.night.changed', {:votee => mfor})
          end
        when :fellowwolf
          m.reply @lang.t('vote.night.samerole')
        when :voteenotplayer
          m.reply @lang.t('vote.noplayer', {:votee => mfor})
        when :dead
          m.reply @lang.t('vote.night.dead')
        when :self
          m.reply @lang.t('vote.night.self')
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
        next if voters.nil?
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
        message = @lang.t('votes.abstain', {
          :count => voters.count,
          :players => voters.join(', ')
        })
      else
        message = @lang.t('votes.message', {
          :votee => votee,
          :count => voters.count,
          :voters => voters.join(', ')
        })
      end
      message = Format(:italic, message) if tiebreak.include?(votee)
      return message
    end

    def opped(m, *args)
      chan, mode, user = m.params
      @game = TWG::Game.new if @game.nil?
      if chan == config["game_channel"] && mode == "+o" && user == bot.nick
        check_ready
      elsif chan == config["game_channel"] && mode == "-o" && user == bot.nick
        if @game.state != :signup || (@game.state == :signup && @signup_started == true)
          chanm @lang.t 'general.deopped'
        end
        @game = nil
        @signup_started = false
        @allow_starts = false
      end
    end

    def allow_starts(m)
      synchronize(:allow_starts) do
        if not @allow_starts
          chanm @lang.t 'general.ready'
          chanm @lang.t 'lang.advertise'
          @allow_starts = true
        end
      end
    end

    def nickchange(m)
      oldname = m.user.last_nick.to_s
      newname = m.user.to_s
      return if @game.nil?
      return if @game.participants[oldname].nil?
      @game.nickchange(oldname, newname)
      return if @game.participants[oldname] == :dead
      chanm @lang.t('general.rename', {
        :oldnick => Format(:bold, m.user.last_nick),
        :nick    => Format(:bold, m.user.to_s)
      })
    end

    def start(m)
      return if !m.channel?
      return if m.channel != config["game_channel"]
      if !@allow_starts
        if opped?
          m.reply @lang.t('general.plzhold', {:nick => m.user.to_s})
        else
          m.reply @lang.t 'general.noops'
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
        wipe_slate
        @signup_started = true
        m.reply @lang.t('start.start', {:nick => m.user.to_s})
        m.reply @lang.t('start.registration', {
          :limit   => config["game_timers"]["registration"].to_s,
          :players => @game.min_part.to_s
        })
        m.reply @lang.t('start.skipmessage')
        @game.register(m.user.to_s)
        voice(m.user)
        hook_async(:ten_seconds_left, config["game_timers"]["registration"] - 10)
        hook_async(:complete_startup, config["game_timers"]["registration"])
      end
    end

    def complete_startup(m)
      return if @game.nil?
      return unless @game.state == :signup
      r = @game.start
      @signup_started = false

      if r.code == :gamestart
        chanm @lang.t('start.starting', {
          :players => @game.participants.keys.sort.join(', ')
        })
        chanm @lang.t('start.rolesoon')
        Channel(config["game_channel"]).mode('+m')
        hook_sync(:hook_roles_assigned)
        hook_async(:hook_notify_roles)
        hook_async(:enter_night, 10)
      elsif r.code == :notenoughplayers
        chanm @lang.t('start.enoughplayers')
        wipe_slate
      else
        chanm Format(:red, @lang.t('start.error'))
        wipe_slate
      end
    end

    def join(m)
      return if !m.channel?
      return if !@signup_started
      if !@game.nil? && @game.state == :signup
        r = @game.register(m.user.to_s)
        if r.code == :confirmplayer
          m.reply @lang.t('start.joined', {
            :player => m.user.to_s,
            :number => @game.participants.length.to_s,
            :min    => @game.min_part.to_s
          })
          Channel(config["game_channel"]).voice(m.user)
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
      return if not m.channel.users.keys.include?(uobj)
      r = @game.register(user)
      if r.code == :confirmplayer
        m.reply @lang.t('start.forcejoined', {
          :player => user,
          :number => @game.participants.length.to_s,
          :min    => @game.min_part.to_s
        })
        Channel(config["game_channel"]).voice(uobj)
      end
    end

    def ten_seconds_left(m)
      return if @game.nil?
      return unless @game.state == :signup
      chanm @lang.t('start.almostready', {
        :secs   => '10',
        :number => @game.participants.length.to_s,
        :min    => @game.min_part.to_s
      })
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
        if elligible.count > 0
          chanm @lang.t('day.almostready.yet', {
            :secs      => secsremain,
            :absentees => elligible.join(', ')
          })
        else
          chanm @lang.t('day.almostready.everybody', {
            :secs => secsremain
          })
        end
      end
    end

    def enter_night(m)
      return if @game.nil?
      chanm @lang.t('night.enter', {
        :night => @game.iteration.to_s,
        :secs => config["game_timers"]["night"].to_s
      })
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
        chanm @lang.t('night.exit.nobody')
      else
        killed = r[0]
        chanm @lang.t('night.exit.body', {
          :killed => killed
        })
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
        chanm @lang.t('day.exit.novotes')
      elsif r == :abstain
        chanm @lang.t('day.exit.abstain')
      elsif r.class == Array
        k = r[0]
        role = r[1]
        chanm @lang.t('day.exit.lynch', {
          :killed => k
        })
        sleep 2
        chanm @lang.t('day.exit.suspense', {
          :killed => k
        })
        sleep(config["game_timers"]["dramatic_effect"])
      end
      if role == :wolf
        chanm @lang.t('day.exit.result.wolf')
        devoice(k)
      elsif r != :abstain
        chanm @lang.t('day.exit.result.normal')
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
          userm(user, @lang.t('roles.normal'))
        when :wolf
          wolfcp = @game.game_wolves.dup
          wolfcp.delete(user)
          userm(user, @lang.t('roles.wolf', {
            :count => @game.game_wolves.count,
            :wolves => wolfcp.join(', ')
          }))
        end
      end
    end

    def check_victory_conditions
      return if @game.nil?
      if @game.state == :wolveswin
        chanm @lang.t('victory.wolfreveal', {
          :count => @game.live_wolves,
          :wolf  => @game.wolves_alive[0]
        })
        if @game.game_wolves.length == 1
          chanm @lang.t('victory.wolf', {:wolf => @game.wolves_alive[0]})
        else
          if @game.live_wolves == @game.game_wolves.length
            chanm @lang.t('victory.wolves.all', {:wolves => @game.game_wolves.join(', ')})
          else
            chanm @lang.t('victory.wolves', {
              :count  => @game.wolves_alive.count,
              :wolves => @game.wolves_alive.join(', ')
            })
          end
        end
        wipe_slate
        return true
      elsif @game.state == :humanswin
        chanm @lang.t('victory.human', {
          :wolves => @game.game_wolves.join(', '),
          :count  => @game.game_wolves.count
        })
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
      message = @lang.t('night.solicit', {
        :count => alive.length,
        :night => @game.iteration
      })
      alive.each do |wolf|
        userm(wolf, message)
      end
    end

    def solicit_human_votes(killed=nil)
      return if @game.nil?
      if killed.nil?
        message = @lang.t('day.enter.solicit.nokill', {
          :day  => @game.iteration,
          :secs => config["game_timers"]["day"].to_s
        })
      else
        message = @lang.t('day.enter.solicit.kill', {
          :day    => @game.iteration,
          :secs   => config["game_timers"]["day"].to_s,
          :killed => killed
        })
      end
      chanm message
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
