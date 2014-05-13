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
      commands = @lang.t_array('vigilante.command')
      commands.each do |command|
        command = Regexp.new(command + " ([^ ]+)(.*)?$")
        self.class.match(command, :method => :shoot)
      end
      __register_matchers
    end

    def pick_vigilante(m)
      odds = config["odds_per_player"] ||= 5
      pick_special(:vigilante, odds)
      bp_count = (@game.participants.count / 3) - 1
      @bulletproof = @game.participants.keys.shuffle[0..bp_count]
      @bulletproof.map! { |p| p.nick }
      debug "Selected bulletproof players: #{@bulletproof.join(', ')}"
    end

    def notify_roles(m)
      return if @game.nil?
      v = vigilante
      return if v.nil?
      v.send @lang.t('vigilante.role.l1')
      v.send @lang.t('vigilante.role.l2')
      info "Role notification sent to #{v.nick}"
    end

    def shoot(m, target, rant)
      return if @game.nil?
      v = vigilante
      target = User(target)
      return if v.nil?
      return if not m.channel?
      return if @game.state != :day
      return if v != m.user
      return if @game.participants[target].nil?
      return if @game.participants[target] == :dead

      if @bulletproof.include?(target)
        @game.participants[v] = :normal

        if v != target
          m.reply @lang.t('vigilante.shoot.other.fail', {
            :vigilante => v.nick,
            :target    => target.nick
          })
        else
          m.reply @lang.t('vigilante.shoot.self.fail', {
            :vigilante => v.nick
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
          :vigilante => v.nick,
          :target    => target.nick
        })
      else
        m.reply @lang.t('vigilante.shoot.self.success', {
          :vigilante => v.nick
        })
      end

      sleep 10
      if v != target
        m.reply @lang.t('vigilante.reaction.other', :target => target.nick)
      else
        m.reply @lang.t('vigilante.reaction.self', :target => target.nick)
      end
      sleep 5

      case r
      when nil
        debug "Error! Valid player was sent to kill, but got nil back"
        debug "#{target.inspect}"
      when :vigilante
        m.reply @lang.t('vigilante.reveal.self', :vigilante => v.nick)
      when :wolf
        m.reply @lang.t('vigilante.reveal.wolf.l1', :target => target.nick)
        m.reply @lang.t('vigilante.reveal.wolf.l2', :target => target.nick, :vigilante => v.nick)
      when :seer
        m.reply @lang.t('vigilante.reveal.seer.l1', :target => target.nick)
        m.reply @lang.t('vigilante.reveal.seer.l2', :vigilante => v.nick)
      else
        brave = players_of_role(:dead, true).shuffle[0]
        m.reply @lang.t('vigilante.reveal.normal.l1', :target => target.nick, :brave => brave.nick)
        m.reply @lang.t('vigilante.reveal.normal.l2', :target => target.nick, :vigilante => v.nick)
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
