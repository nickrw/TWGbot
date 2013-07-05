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

      hook_cancel(:warn_vote_timeout)
      hook_cancel(:exit_day)

      if v != target
        m.reply @lang.t('vigilante.shoot.other', {
          :vigilante => m.user.to_s,
          :target    => target
        })
        @game.participants[v] = :normal
      else
        m.reply @lang.t('vigilante.shoot.self', {
          :vigilante => m.user.to_s
        })
      end
      r = @game.kill(target)
      @core.devoice(target)

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
      @game.next_state
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
