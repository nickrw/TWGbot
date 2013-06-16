require 'twg/plugin'

module TWG
  class Seer < TWG::Plugin
    include Cinch::Plugin
    listen_to :hook_roles_assigned, :method => :pick_seer
    listen_to :hook_notify_roles,   :method => :notify_roles
    listen_to :hook_votes_applied,  :method => :seer_reveal
    listen_to :enter_night,         :method => :solicit_seer_choice
    listen_to :nick,                :method => :nickchange
    match /see ([^ ]+)$/,           :method => :see

    def initialize(*args)
      super
      reset
    end

    def pick_seer(m)
      pick_special(:seer, 6)
    end

    def solicit_seer_choice(m)
      return if @game.nil?
      reset
      @seer = seer
      return if @seer.nil?
      User(@seer).send "It is now NIGHT %s: say !see <nickname> to me to reveal their role." % @game.iteration.to_s
    end

    def seer_reveal(m)
      return if @game.nil?
      return if @game.state != :night
      return if @seer.nil?
      return if @target.nil?
      if seer != @seer
        User(@seer).send "While dreaming vividly about %s you get viciously torn to pieces. Your magic 8 ball didn't see that one coming!" % @target
        reset
        return
      end
      t = @game.participants[@target]
      case t
        when :dead
          User(@seer).send "You have a vision of %s's body, twisted, broken and bloody. A wolf got there before you." % @target
        when :wolf
          User(@seer).send "You have a dream about %s wearing a new fur coat. You've found a WOLF." % @target
        when :vigilante
          User(@seer).send "You have a dream about %s shooting. It looks like %s is a fellow villager." % [@target, @target]
        else
          User(@seer).send "You have a dream about %s shouting. It looks like %s is a fellow villager." % [@target, @target]
      end
      reset
    end

    def notify_roles(m)
      return if @game.nil?
      s = seer
      return if s.nil?
      User(s).send "You are the SEER. Each night you can have the role of a player of your choice revealed. Choose carefully, once the inner eye has selected a target it cannot be swayed."
    end

    def see(m, target)
      return if @game.nil?
      return if m.channel?
      s = seer
      return if s.nil?
      return if s != m.user.nick

      if @game.state != :night
        m.reply "You're wide awake - this is no time for visions!"
        return
      end

      t = @game.participants[target]
      if t.nil?
        m.reply "#{target} isn't a player in this game"
        return
      end

      if target == s
        m.reply "Surely you know what you are... try again."
        return
      end

      if t == :dead
        m.reply "#{target} is dead, try again."
        return
      end

      if @target.nil?
        m.reply "#{target}'s identity will be revealed to you as you wake."
      else
        m.reply "You have changed the target of tonight's vision to #{target}."
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
