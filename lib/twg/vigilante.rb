require 'twg/plugin'

module TWG
  class Vigilante < TWG::Plugin
    include Cinch::Plugin
    listen_to :hook_roles_assigned, :method => :pick_vigilante
    listen_to :hook_notify_roles, :method => :notify_roles

    def self.description
      "Special role which can kill any player during the day (single use)"
    end

    def initialize(*args)
      super
      command = Regexp.new(@lang.t('vigilante.command') + " ([^ ]+)(.*)?$")
      self.class.match(command, :method => :shoot)
      __register_matchers
    end

    def pick_vigilante(m)
      odds = config["odds_per_player"] ||= 5
      pick_special(:vigilante, odds)
      bp_count = (@game.participants.count / 3) - 1
      @bulletproof = @game.participants.keys.shuffle[0..bp_count]
      debug "Selected bulletproof players: #{@bulletproof.join(', ')}"
    end

    def notify_roles(m)
      return if @game.nil?
      v = vigilante
      return if v.nil?
      User(v).send @lang.t('vigilante.role.l1')
      User(v).send @lang.t('vigilante.role.l2')
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

      if @bulletproof.include?(target)
        @game.participants[v] = :normal

        if v != target
          m.reply @lang.t('vigilante.shoot.other.fail', {
            :vigilante => m.user.to_s,
            :target    => target
          })
        else
          m.reply @lang.t('vigilante.shoot.self.fail', {
            :vigilante => m.user.to_s
          })
        end

        return
      end

      hook_cancel(:warn_vote_timeout)
      hook_cancel(:exit_day)
      r = @game.kill(target)
      @game.participants[v] = :normal
      @core.devoice(target)
      @game.next_state

      if v != target
        m.reply @lang.t('vigilante.shoot.other.success', {
          :vigilante => m.user.to_s,
          :target    => target
        })
      else
        m.reply @lang.t('vigilante.shoot.self.success', {
          :vigilante => m.user.to_s
        })
      end

      sleep 10
      if v != target
        m.reply @lang.t('vigilante.reaction.other', :target => target)
      else
        m.reply @lang.t('vigilante.reaction.self', :target => target)
      end
      sleep 5

      case r
      when nil
        debug "Error! Valid player was sent to kill, but got nil back"
        debug "#{target.inspect}"
      when :vigilante
        m.reply @lang.t('vigilante.reveal.self', :vigilante => m.user.to_s)
      when :wolf
        m.reply @lang.t('vigilante.reveal.wolf.l1', :target => target)
        m.reply @lang.t('vigilante.reveal.wolf.l2', :target => target, :vigilante => m.user.to_s)
      when :seer
        m.reply @lang.t('vigilante.reveal.seer.l1', :target => target)
        m.reply @lang.t('vigilante.reveal.seer.l2', :vigilante => m.user.to_s)
      else
        brave = players_of_role(:dead, true).shuffle[0]
        m.reply @lang.t('vigilante.reveal.normal.l1', :target => target, :brave => brave)
        m.reply @lang.t('vigilante.reveal.normal.l2', :target => target, :vigilante => m.user.to_s)
      end

      sleep 3
      unless @core.check_victory_conditions
        m.reply @lang.t('vigilante.over')
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
