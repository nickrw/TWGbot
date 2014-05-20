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
    listen_to :hook_signup_complete, :method => :complete_startup
    listen_to :hook_notify_roles, :method => :notify_roles
    listen_to :nick, :method => :nickchange
    listen_to :join, :method => :channel_join
    listen_to :op, :method => :opped
    listen_to :deop, :method => :opped
    listen_to :hook_allow_starts, :method => :allow_starts
    listen_to :hook_shutdown, :method => :shutdown
    listen_to :hook_openup, :method => :openup

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
        :start      => @lang.t_array('command.start'),
        :vote       => @lang.t_array('command.vote').map{|c| Regexp.new(c + " ([^ ]+)(.*)?$") },
        :abstain    => @lang.t_array('command.abstain').map{|c| Regexp.new(c + "( .*)?$") },
        :votes      => @lang.t_array('command.votes'),
        :join       => @lang.t_array('command.join'),
        :forcejoin  => @lang.t_array('command.join').map{|c| Regexp.new(c + " ([^ ]+)$") },
        :langlist   => @lang.t_array('command.langs'),
        :selectlang => @lang.t_array('command.lang').map{|c| Regexp.new(c + " ([^ ]+)$") }
      }

      commands.each do |method,patterns|
        patterns.each do |pattern|
          self.class.match(pattern, :method => method)
        end
      end
      __register_matchers

      shared[:game] = @game
      @timer = nil
      @allow_starts = false
      @shutdown_reason = ""
      check_ready
    end

    def coreconfig
      config
    end

    def langlist(m)
      return if !m.channel?
      return if m.channel != config["game_channel"]
      return if not @allow_starts
      case @game.state
      when nil, :signup, :wolveswin, :humanswin
        m.reply @lang.t 'lang.packs.all'
        TWG::Lang.list.each do |pack, desc|
          message = "#{pack}: #{desc}"
          if @lang.pack == pack
            message = Format(:italic, message)
          end
          m.reply message
        end
      else
        m.reply @lang.t 'lang.packs.current', :lang => @lang.pack.to_s
      end
    end

    def selectlang(m, lang)
      return if !m.channel?
      return if m.channel != config["game_channel"]
      return if not @allow_starts
      case @game.state
      when nil, :signup, :wolveswin, :humanswin
      else
        m.reply @lang.t 'lang.packs.current', :lang => @lang.pack.to_s
        return
      end
      case @lang.select(lang.to_sym)
      when :inactive
        m.reply @lang.t('lang.inactive', {:lang => lang})
      when :notfound
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
      u = m.user
      if @game.abstain(u) == true
        if @game.state == :night
          m.reply @lang.t('vote.night.abstain')
        else
          m.reply @lang.t('vote.day.abstain', {:voter => u.nick})
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
        return if @allow_starts
        @allow_starts = false
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
      u = m.user
      if u.nick == bot.nick
        check_ready
      else
        # refresh to ensure user case is accurate
        u.refresh
        return if @game.nil?
        return if @game.participants[u].nil?
        return if @game.participants[u] == :dead
        voice(u)
      end
    end

    def vote(m, vfor, reason)
      return if @game.nil?
      u = m.user
      vfor = User(vfor)
      is_channel = (m.channel? ? :channel : :private)
      r = @game.vote(u, vfor, is_channel)

      if m.channel?

        case r[:code]
        when :confirmvote
          if r[:previous].nil? || r[:previous] == :abstain
            m.reply @lang.t('vote.day.vote', {
              :voter => u.nick,
              :votee => Format(:bold, vfor.nick)
            })
          else
            m.reply @lang.t('vote.day.changed', {
              :voter     => u.nick,
              :origvotee => r[:previous],
              :votee     => Format(:bold, vfor.nick)
            })
          end
        when :voteenotplayer
          m.reply @lang.t('vote.noplayer', {:votee => vfor.nick})
        when :voteedead
          m.reply @lang.t('vote.day.dead', {
            :voter => u.nick,
            :votee => vfor.nick
          })
        end

      else

        case r[:code]
        when :confirmvote
          if r[:previous].nil?
            m.reply @lang.t('vote.night.vote', {:votee => vfor.nick})
          else
            m.reply @lang.t('vote.night.changed', {:votee => vfor.nick})
          end
        when :fellowwolf
          m.reply @lang.t('vote.night.samerole')
        when :voteenotplayer
          m.reply @lang.t('vote.noplayer', {:votee => vfor.nick})
        when :dead
          m.reply @lang.t('vote.night.dead')
        when :self
          m.reply @lang.t('vote.night.self')
        end

      end
    end

    def votes(m)
      return if @game.state != :day
      tiebreak = @game.apply_votes(false)
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
      if votee.class == Cinch::User
        votee = votee.nick
      end
      voters = voters.map { |p| p.nick }
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

    def disallow_starts(m)
      synchronize(:allow_starts) do
        if @allow_starts
          @allow_starts = false
        end
      end
    end

    def shutdown(m, reason)
      @shutdown_reason = reason
      if @signup_started == true
        hook_cancel(:ten_seconds_left)
        hook_cancel(:hook_signup_complete)
        wipe_slate
        return
      end
    end

    def openup(m)
      @shutdown_reason = ""
    end

    def nickchange(m)
      u = m.user
      oldname = u.last_nick
      newname = u.nick
      return if @game.nil?
      return if @game.participants[u].nil?
      #@game.nickchange(oldname, newname)
      return if @game.participants[u] == :dead
      chanm @lang.t('general.rename', {
        :oldnick => Format(:bold, oldname),
        :nick    => Format(:bold, newname)
      })
    end

    def start(m)
      return if !m.channel?
      return if m.channel != config["game_channel"]
      u = m.user
      if !@allow_starts
        if opped?
          m.reply @lang.t('general.plzhold', {:nick => u.nick})
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
          hook_expedite(:hook_signup_complete)
          return
        end
      end
      if not @shutdown_reason.empty?
        m.reply @lang.t('start.shutdown', {:reason => @shutdown_reason})
        return
      end
      if @game.state.nil? || @game.state == :wolveswin || @game.state == :humanswin
        @game.reset
      end
      if @game.state == :signup
        wipe_slate
        @signup_started = true
        m.reply @lang.t('start.start', {:nick => u.nick})
        m.reply @lang.t('start.registration', {
          :limit   => config["game_timers"]["registration"].to_s,
          :players => @game.min_part.to_s
        })
        m.reply @lang.t('start.skipmessage')
        @game.register(u)
        voice(u)
        hook_async(:ten_seconds_left, config["game_timers"]["registration"] - 10)
        hook_async(:hook_signup_complete, config["game_timers"]["registration"])
        hook_async(:hook_signup_started)
      end
    end

    def complete_startup(m)
      return if @game.nil?
      return unless @game.state == :signup
      r = @game.start
      @signup_started = false

      if r.code == :gamestart
        players = @game.participants.keys.sort.map { |p| p.nick }
        chanm @lang.t('start.starting', {
          :players => players.join(", ")
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
        u = m.user
        r = @game.register(u)
        if r.code == :confirmplayer
          m.reply @lang.t('start.joined', {
            :player => u.nick,
            :number => @game.participants.length.to_s,
            :min    => @game.min_part.to_s
          })
          voice(u)
        end
      end
    end

    def forcejoin(m, user)
      return if not m.channel?
      return if not admin?(m.user)
      return if not @signup_started
      return if @game.nil?
      return if @game.state != :signup
      u = User(user)
      return if not m.channel.users.keys.include?(u)
      r = @game.register(u)
      if r.code == :confirmplayer
        m.reply @lang.t('start.forcejoined', {
          :player => u.nick,
          :number => @game.participants.length.to_s,
          :min    => @game.min_part.to_s
        })
        voice(u)
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
        elligible.map! { |p| p.nick }
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
      hook_sync(:hook_pre_enter_night, nil, config)
      chanm @lang.t('night.enter', {
        :night => @game.iteration.to_s,
        :secs => config["game_timers"]["night"].to_s
      })
      @game.state_transition_in
      solicit_wolf_votes
      hook_async(:exit_night, config["game_timers"]["night"])
      hook_sync(:hook_post_enter_night, nil, config)
    end

    def exit_night(m,opts=nil)
      return if @game.nil?
      hook_sync(:hook_pre_exit_night,m,opts)
      r = @game.apply_votes
      hook_sync(:hook_night_votes_applied,m,opts)
      @game.next_state
      killed = nil
      if r.nil? || r == :abstain
        chanm @lang.t('night.exit.nobody')
      else
        killed = r[0]
        chanm @lang.t('night.exit.body', {
          :killed => killed.nick
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
      hook_sync(:hook_day_votes_applied)
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
          :killed => k.nick
        })
        sleep 2
        chanm @lang.t('day.exit.suspense', {
          :killed => k.nick
        })
        sleep(config["game_timers"]["dramatic_effect"])
      end
      if role == :wolf
        chanm @lang.t('day.exit.result.wolf')
        devoice(k)
      elsif !r.nil? && r != :abstain
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
          user.send(@lang.t('roles.normal'))
        when :wolf
          wolfcp = @game.game_wolves.dup
          wolfcp.delete(user)
          wolfcp.map! { |p| p.nick }
          user.send(@lang.t('roles.wolf', {
            :count => @game.game_wolves.count,
            :wolves => wolfcp.join(', ')
          }))
        end
      end
    end

    def check_victory_conditions
      return if @game.nil?
      all_wolves = @game.game_wolves.map { |p| p.nick }
      wolves_alive = @game.wolves_alive.map { |p| p.nick }
      if @game.state == :wolveswin
        chanm @lang.t('victory.wolfreveal', {
          :count => wolves_alive.count,
          :wolf  => wolves_alive[0]
        })
        if @game.game_wolves.length == 1
          chanm @lang.t('victory.wolf', {:wolf => wolves_alive[0]})
        else
          if @game.live_wolves == @game.game_wolves.length
            chanm @lang.t('victory.wolves.all', {:wolves => all_wolves.join(', ')})
          else
            chanm @lang.t('victory.wolves', {
              :count  => wolves_alive.count,
              :wolves => wolves_alive.join(', ')
            })
          end
        end
        wipe_slate
        return true
      elsif @game.state == :humanswin
        chanm @lang.t('victory.human', {
          :wolves => all_wolves.join(', '),
          :count  => all_wolves.count
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

    def solicit_wolf_votes
      return if @game.nil?
      alive = @game.wolves_alive
      message = @lang.t('night.solicit', {
        :count => alive.length,
        :night => @game.iteration
      })
      alive.each do |wolf|
        wolf.send(message)
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
          :killed => killed.nick
        })
      end
      chanm message
    end

    def chanm(m)
      Channel(config["game_channel"]).send(m)
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
