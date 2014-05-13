require 'twg/plugin'

module TWG
  class Seer < TWG::Plugin
    include Cinch::Plugin
    listen_to :hook_roles_assigned,       :method => :pick_seer
    listen_to :hook_notify_roles,         :method => :notify_roles
    listen_to :hook_night_votes_applied,  :method => :seer_reveal
    listen_to :enter_night,               :method => :solicit_seer_choice

    def self.description
      "Special role which can reveal other players' roles at night"
    end

    def initialize(*args)
      super
      commands = @lang.t_array('seer.command')
      commands.each do |command|
        command = Regexp.new(command + " ([^ ]+)$")
        self.class.match(command, :method => :see)
      end
      __register_matchers
      reset
    end

    def pick_seer(m)
      odds = config["odds_per_player"] ||= 6
      pick_special(:seer, odds)
    end

    def solicit_seer_choice(m)
      return if @game.nil?
      reset
      @seer = seer
      return if @seer.nil?
      @seer.send @lang.t('seer.solicit', :night => @game.iteration.to_s)
    end

    def seer_reveal(m,opts)
      return if @game.nil?
      return if @game.state != :night
      return if @seer.nil?
      return if @target.nil?
      tnick = @target.nick
      if seer != @seer
        @seer.send @lang.t('seer.killed', :target => tnick)
        reset
        return
      end
      t = @game.participants[@target]
      t = :normal if not [:dead, :wolf, :vigilante].include?(t)
      @seer.send @lang.t("seer.reveal.#{t.to_s}", :target => tnick)
      reset
    end

    def notify_roles(m)
      return if @game.nil?
      s = seer
      return if s.nil?
      s.send @lang.t('seer.role')
    end

    def see(m, target)
      return if @game.nil?
      return if m.channel?
      s = seer
      return if s.nil?
      return if s != m.user.nick

      target = User(target)

      if @game.state != :night
        m.reply @lang.t('seer.awake')
        return
      end

      t = @game.participants[target]
      if t.nil?
        m.reply @lang.t('seer.target.nosuch', :target => target.nick)
        return
      end

      if target == s
        m.reply @lang.t('seer.target.self')
        return
      end

      if t == :dead
        m.reply @lang.t('seer.target.dead', :target => target.nick)
        return
      end

      if @target.nil?
        m.reply @lang.t('seer.target.confirm', :target => target.nick)
      else
        m.reply @lang.t('seer.target.change', :target => target.nick)
      end

      @target = target
    end

    private

    def seer
      s = players_of_role(:seer)
      s[0]
    end

    def reset
      @seer = nil
      @target = nil
    end

  end
end
