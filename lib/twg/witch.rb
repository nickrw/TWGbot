require 'twg/plugin'

module TWG
  class Witch < TWG::Plugin
    include Cinch::Plugin
    listen_to :hook_roles_assigned,       :method => :pick_witch
    listen_to :hook_notify_roles,         :method => :notify_roles
    listen_to :enter_night,               :method => :witch_on_your_marks
    listen_to :hook_post_enter_night,     :method => :witch_set_get_set
    listen_to :hook_witch_get_set,        :method => :witch_get_set
    listen_to :hook_witch_exit_night,     :method => :override_exit_night
    listen_to :hook_pre_exit_night,       :method => :witch_go
    listen_to :nick,                      :method => :nickchange

    def self.description
      "Special role which can prevent a player from dying at night"
    end

    def initialize(*args)
      super
      commands = @lang.t_array('witch.command')
      commands.each do |command|
        command = Regexp.new(command + "(?: ([^ ]+))?$")
        self.class.match(command, :method => :witch_save)
      end
      __register_matchers
      reset
    end

    def pick_witch(m)
      reset
      odds = config["odds_per_player"] ||= 5
      pick_special(:witch, odds)
    end

    def notify_roles(m)
      return if @game.nil?
      w = witch
      return if w.nil?
      w.send @lang.t('witch.role')
    end

    def witch_on_your_marks(m)
      return if @game.nil?
      reset
      @witch = witch
      return if @witch.nil?
      @witch.send @lang.t('witch.prepare', :night => @game.iteration.to_s)
    end

    def witch_set_get_set(m, coreconfig)
      hook_async(:hook_witch_get_set, coreconfig["game_timers"]["night"] - 10)
    end

    def witch_get_set(m)
      return if @game.nil?
      return if @witch.nil?
      @witch.send @lang.t('witch.tensecs', :night => @game.iteration.to_s)
    end

    def witch_go(m, *args)

      # No recursion thanks
      return if args.include?(:witch)

      return if @game.nil?

      # Prevent normal votes from going through
      # Unlocking is performed automatically when the game advances to the
      # next state and is not necessary here. Any vote rigging done by 
      # #witch_save is exempt from the lock.
      @game.lock

      # Inform the wolves that voting is over
      # and that further votes will be ignored
      wolves = players_of_role(:wolf)
      wolves.each do |wolf|
        wolf.send(@lang.t('witch.wolfvoteover'))
      end

      if @witch.nil?
        sleep 10
        return
      end

      @target = @game.apply_votes(false)
      @target.delete(:abstain)

      if @target.empty?
        @witch.send @lang.t('witch.peaceful')
        sleep 10
        return
      end

      if @target.count == 1 && @target.include?(@witch)
        @witch.send @lang.t('witch.peaceful')
        sleep 5
        @witch.send @lang.t('witch.comingforyou')
        sleep 3
        @witch.send @lang.t('witch.toolate')
        sleep 2
        reset
        return
      end

      target = @target.dup.map { |p| p.nick }

      if @target.include?(@witch)

        target.delete(@witch.nick)

        @witch.send @lang.t(
          'witch.choosedanger',
          :count => target.count,
          :target => target.join(', ')
        )
        @witch.send @lang.t(
          'witch.choosedanger.instruct',
          :count => target.count
        )

      else

        @witch.send @lang.t(
          'witch.choose',
          :count => target.count,
          :target => target.join(', ')
        )
        @witch.send @lang.t(
          'witch.choose.instruct',
          :count => target.count
        )

      end

      @standby = true
      hook_async(:hook_witch_exit_night, 10, nil, @witch)
      # The thread this method runs in is Thread#join'd by
      # TWG::Core#exit_night - we want to abort and handle it manually
      raise PluginOverrideException

    end

    def override_exit_night(m, witchwas)
      synchronize(:twg_witch_standby) do 
        @standby = false
        target = @game.apply_votes(false)
        target.delete(:abstain)
        w = witch
        if (not target.empty?) || w == witchwas
          # The witch took failed, or no, action
          hook_async(:exit_night,0,nil,:witch)
        else
          @game.apply_votes
          hook_sync(:hook_night_votes_applied,nil,:witch)
          @game.next_state
          if target.empty? && w != witchwas
            chansay('witch.channelsuccess',
              :saved => @saved.nick
            )
            @saved.send(@lang.t('witch.privatesuccess',
              :witch => witchwas.nick
            ))
          end
          unless @core.check_victory_conditions
            hook_async(:enter_day, 0, nil, nil)
          end
        end
        reset
      end
    end

    def witch_save(m, save)
      return if @game.nil?
      return if m.channel?
      return if @witch.nil?
      return if @witch != m.user.nick
      synchronize(:twg_witch_standby) do

        return if not @standby

        if @game.state != :night
          m.reply @lang.t('witch.awake')
          return
        end

        if @target.count == 1
          # There is only one target. Saviour is unambiguous.

          @game.clear_votes
          target = @target[0]
          @saved = target
          demote
          m.reply @lang.t('witch.unambiguous',
                          :target => target
                         )

        elsif @target.count > 1
          # The game will pick randomly between the targets later
          # Do it now and rig the vote instead.

          target = @target.dup
          target.delete(@witch) if target.include?(@witch)

          if save.nil?
            # The witch didn't specify a target. Protection is random.
            save = target.shuffle[0]
          else
            save = User(save)
          end

          if not target.include?(save)
            # The witch manually specified a target (save) but it doesn't
            # seem to be a valid one.
            m.reply @lang.t('witch.nottarget', :player => save.nick)
          end

          kill = @target.shuffle[0]

          if kill == save
            # Nobody's dying on our watch, dammit.
            @game.clear_votes
            @saved = save
            demote
            m.reply @lang.t('witch.ambiguous.success', :player => save.nick)
          else
            # Rig the votes so it won't be a tiebreak when #apply_votes gets
            # called by #exit_night
            lstr = 'witch.ambiguous.fail'
            if kill == @witch
              lstr = 'witch.ambiguous.failhard'
            end
            @game.vote(:witch, kill, :night)
            demote
            m.reply @lang.t(lstr, :save => save.nick, :target => kill.nick)
          end

        end

      end
    end

    private

    def witch
      s = players_of_role(:witch)
      s[0]
    end

    def demote
      w = witch
      if w && @game.participants[w] == :witch
        @game.participants[w] = :normal
      end
      @witch = nil
    end

    def reset
      @witch = nil
      @target = nil
      @standby = false
      @saved = nil
    end

  end
end
