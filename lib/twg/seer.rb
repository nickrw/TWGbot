require 'twg/plugin'

module TWG
  class Seer < TWG::Plugin
    include Cinch::Plugin
    listen_to :hook_roles_assigned,       :method => :pick_seer
    listen_to :hook_notify_roles,         :method => :notify_roles
    listen_to :hook_night_votes_applied,  :method => :seer_reveal
    listen_to :enter_night,               :method => :solicit_seer_choice
    listen_to :nick,                      :method => :nickchange

    def self.description
      "Special role which can reveal other players' roles at night"
    end

    def initialize(*args)
      super
      command = Regexp.new(@lang.t('seer.command') + " ([^ ]+)$")
      self.class.match(command, :method => :see)
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
      User(@seer).send @lang.t('seer.solicit', :night => @game.iteration.to_s)
    end

    def seer_reveal(m,opts)
      return if @game.nil?
      return if @game.state != :night
      return if @seer.nil?
      return if @target.nil?
      if seer != @seer
        User(@seer).send @lang.t('seer.killed', :target => @target)
        reset
        return
      end
      t = @game.participants[@target]
      case t
        when :dead
          User(@seer).send @lang.t('seer.reveal.dead', :target => @target)
        when :wolf
          User(@seer).send @lang.t('seer.reveal.wolf', :target => @target)
        when :vigilante
          User(@seer).send @lang.t('seer.reveal.vigilante', :target => @target)
        else
          User(@seer).send @lang.t('seer.reveal.normal', :target => @target)
      end
      reset
    end

    def notify_roles(m)
      return if @game.nil?
      s = seer
      return if s.nil?
      User(s).send @lang.t('seer.role')
    end

    def see(m, target)
      return if @game.nil?
      return if m.channel?
      s = seer
      return if s.nil?
      return if s != m.user.nick

      if @game.state != :night
        m.reply @lang.t('seer.awake')
        return
      end

      t = @game.participants[target]
      if t.nil?
        m.reply @lang.t('seer.target.nosuch', :target => target)
        return
      end

      if target == s
        m.reply @lang.t('seer.target.self')
        return
      end

      if t == :dead
        m.reply @lang.t('seer.target.dead', :target => target)
        return
      end

      if @target.nil?
        m.reply @lang.t('seer.target.confirm', :target => target)
      else
        m.reply @lang.t('seer.target.change', :target => target)
      end

      @target = target
    end

    def nickchange(m)
      oldname = m.user.last_nick.to_s
      newname = m.user.to_s
      @seer = newname if @seer == oldname
      @target = newname if @target == oldname
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
