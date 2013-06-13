module TWG
  class IRC
    class Vigilante
      include Cinch::Plugin
      listen_to :hook_roles_assigned, :method => :pick_vigilante
      listen_to :hook_notify_roles, :method => :notify_roles
      match /shoot ([^ ]+)(.*)?$/, :method => :shoot

      def initialize(*args)
        super
        i = bot.plugins.find_index { |x| x.class == TWG::IRC }
        @gamemaster = bot.plugins[i]
        debug "Found game master class at bot.plugins[#{i}]: #{@gamemaster.class}"
      end

      def pick_vigilante(m)
        p = players_of_role(:normal)
        odds = p.count * 5 # 5% chance per-villager
        debug "Picking vigilante, with #{odds}% chance of success..."
        r = rand(100)
        if r <= odds
          v = p.shuffle[0]
          shared[:game].participants[v] = :vigilante
          debug "Selected player: #{v} (#{r} <= #{odds})"
        else
          debug "No player selected (#{r} > #{odds})"
        end
      end

      def notify_roles(m)
        return if shared[:game].nil?
        v = vigilante
        return if v.nil?
        User(v).send "You are the VIGILANTE. You have perfected the technology of gunpowder, but you only have enough silver for one bullet."
        User(v).send "Once during any DAY you can say !shoot <player> (in the channel, not privately) to immediately kill that player and end the day."
      end

      def shoot(m, target, rant)
        return if shared[:game].nil?
        v = vigilante
        return if v.nil?
        return if not m.channel?
        return if shared[:game].state != :day
        return if v != m.user.nick
        return if shared[:game].participants[target].nil?
        return if shared[:game].participants[target] == :dead
        debug "Cancelling end-of-day timer"
        @gamemaster.cancel_dispatch
        @gamemaster.timer = nil
        m.reply "%s pulls out a gun and shoots %s" % [m.user.nick, Format(:red, target)]
        r = shared[:game].kill(target)
        shared[:game].participants[v] = :normal
        @gamemaster.devoice(target)
        sleep 10
        m.reply "The villagers, despite their shock at the sudden discovery of gunpowder and ballistics, shuffle forward to look at #{target}'s fallen body..."
        sleep 5
        case r
        when nil
          debug "Error! Valid player was sent to kill, but got nil back"
          debug "#{target.inspect}"
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
        shared[:game].next_state
        unless @gamemaster.check_victory_conditions
          m.reply "The villagers all agree that a bit of a sit down and an early bedtime is in order after the day's exciting events"
          bot.handlers.dispatch(:enter_night,nil)
        end
      end

      private

      def players_of_role(role = :normal, invert = false)
        a = []
        shared[:game].participants.each do |player, r|
          if role.class == Symbol
            next if (r == role && invert) || (r != role && !invert)
            a << player
          elsif role.class == Array
            next if (role.include?(r) && invert) || (!role.include?(r) && !invert)
            a << player
          end
        end
        a
      end

      def vigilante
        av = players_of_role(:vigilante)
        av[0]
      end

    end
  end
end
