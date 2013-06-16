require 'twg/plugin'

module TWG
  class Vigilante < TWG::Plugin
    include Cinch::Plugin
    listen_to :hook_roles_assigned, :method => :pick_vigilante
    listen_to :hook_notify_roles, :method => :notify_roles
    match /shoot ([^ ]+)(.*)?$/, :method => :shoot

    def pick_vigilante(m)
      pick_special(:vigilante)
    end

    def notify_roles(m)
      return if @game.nil?
      v = vigilante
      return if v.nil?
      User(v).send "You are the VIGILANTE. You have perfected the technology of gunpowder, but you only have enough silver for one bullet."
      User(v).send "Once during any DAY you can say !shoot <player> (in the channel, not privately) to immediately kill that player and end the day."
      info "Role notification sent to #{v}"
    end

    def shoot(m, target, rant)
      return if @game.nil?
      v = vigilante
      return if v.nil?
      return if not m.channel?
      return if @game.state != :day
      return if v != m.user.nick
      return if @game.participants[target].nil?
      return if @game.participants[target] == :dead

      hook_cancel(:warn_vote_timeout)
      hook_cancel(:exit_day)

      if v != target
        m.reply "%s pulls out a gun and shoots %s" % [m.user.nick, Format(:red, target)]
        @game.participants[v] = :normal
      else
        m.reply "%s pulls out a gun and %s" % [m.user.nick, Format(:red, "commits suicide")]
      end
      r = @game.kill(target)
      @core.devoice(target)

      sleep 10
      if v != target
        m.reply "The villagers, despite their shock at the sudden discovery of gunpowder and ballistics, shuffle forward to look at #{target}'s fallen body..."
      else
        m.reply "The villagers had known that #{target} was feeling a bit down in the dumps, but had always dismissed it as hormones."
      end
      sleep 5

      case r
      when nil
        debug "Error! Valid player was sent to kill, but got nil back"
        debug "#{target.inspect}"
      when :vigilante
        m.reply "%s's single silver bullet was put to waste in its maker's skull instead of a wolf." % m.user.nick
      when :wolf
        m.reply "... and jump back in horror as #{target} lets out a buttock-clenching death-howl!"
        m.reply "%s's single silver bullet found its true home. %s was a wolf!" % [m.user.nick, Format(:bold, target)]
      when :seer
        m.reply "... and a tinkling crash cuts through the silence as a crystal ball rolls from #{target}'s sleeve."
        m.reply "%s just shot the seer! What rotten luck." % m.user.nick
      else
        brave = players_of_role(:dead, true).shuffle[0]
        m.reply "... the brave #{brave} steps forward and rolls #{target} over with their toe, but nothing happens."
        m.reply "%s's single silver bullet was wasted on %s - a fellow villager." % [m.user.nick, Format(:bold, target)]
      end

      sleep 3
      @game.next_state
      unless @core.check_victory_conditions
        m.reply "The villagers all agree that a bit of a sit down and an early bedtime is in order after the day's exciting events"
        hook_async(:enter_night)
      end

    end

    private

    def vigilante
      av = players_of_role(:vigilante)
      av[0]
    end

  end
end
