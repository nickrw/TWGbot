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
      command = Regexp.new(@lang.t('witch.command') + "(?: ([^ ]+))?$")
      self.class.match(command, :method => :witch_save)
      __register_matchers
      reset
    end

    def pick_witch(m)
      reset
      odds = config["odds_per_player"] ||= 100 #FIXME
      pick_special(:witch, odds)
    end

    def notify_roles(m)
      return if @game.nil?
      w = witch
      return if w.nil?
      User(w).send @lang.t('witch.role')
    end

    def witch_on_your_marks(m)
      return if @game.nil?
      reset
      @witch = witch
      return if @witch.nil?
      User(@witch).send @lang.t('witch.prepare', :night => @game.iteration.to_s)
    end

    def witch_set_get_set(m, coreconfig)
      hook_async(:hook_witch_get_set, coreconfig["game_timers"]["night"] - 10)
    end

    def witch_get_set(m)
      return if @game.nil?
      return if @witch.nil?
      User(@witch).send @lang.t('witch.tensecs', :night => @game.iteration.to_s)
    end

    def witch_go(m, *args)

      # No recursion thanks
      return if args.include?(:witch)

      return if @game.nil?
      if @witch.nil?
        sleep 10
        return
      end

      @target = @game.apply_votes(false)
      @target.delete(:abstain)

      if @target.empty?
        User(@witch).send @lang.t('witch.peaceful')
        sleep 10
        return
      end

      if @target.count == 1 && @target.include?(@witch)
        User(@witch).send @lang.t('witch.peaceful') #I18N TODO
        sleep 5
        User(@witch).send @lang.t('witch.comingforyou') #I18N TODO
        sleep 3
        User(@witch).send @lang.t('witch.toolate') #I18N TODO
        sleep 2
        reset
        return
      end

      langsuffix = @target.include?(@witch) ? ".andyou" : ""

      if @target.include?(@witch)

        target = @target.dup
        target.delete(@witch)

        User(@witch).send @lang.t(
          'witch.choosedanger',
          :count => target.count,
          :target => target.join(', ')
        )
        User(@witch).send @lang.t(
          'witch.choosedanger.instruct',
          :count => target.count
        )

      else

        User(@witch).send @lang.t(
          'witch.choose',
          :count => @target.count,
          :target => @target.join(', ')
        )
        User(@witch).send @lang.t(
          'witch.choose.instruct',
          :count => @target.count
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
          r = @game.apply_votes
          hook_sync(:hook_night_votes_applied,nil,:witch)
          @game.next_state
          if target.empty? && w != witchwas
            debug "Say to channel that the with made it all ok"
            #chanm @lang.t('witch.night.exit.success', {
            #  :saved => @saved
            #})
            # TODO i18n
          end
          unless @core.check_victory_conditions
            hook_async(:enter_day, 0, nil, nil)
          end
        end
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
          reset
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
          end

          if not target.include?(save)
            # The witch manually specified a target (save) but it doesn't
            # seem to be a valid one. FIXME: make this case insensitive
            m.reply @lang.t('witch.nottarget', :player => save)
          end

          kill = @target.shuffle[0]

          if kill == save
            # Nobody's dying on our watch, dammit.
            @game.clear_votes
            @saved = save
            demote
            reset
            m.reply @lang.t('witch.ambiguous.success', :player => save)
          else
            # Rig the votes so it won't be a tiebreak when #apply_votes gets
            # called by #exit_night
            lstr = 'witch.ambiguous.fail'
            if kill == @witch
              lstr = 'witch.ambiguous.failhard'
            end
            @game.vote(:witch, kill, :night)
            demote
            reset
            m.reply @lang.t(lstr, :save => save, :target => kill)
          end

        end

      end
    end

    def nickchange(m)
      oldname = m.user.last_nick.to_s
      newname = m.user.to_s
      @seer = witch if @seer == witch
      if @target.class == Array
        if @target.include?(oldname)
          @target.delete(oldname)
          @target << newname
        end
      else
        @target = newname if @target == oldname
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
    end

    def reset
      @witch = nil
      @target = nil
      @standby = false
      @saved = nil
    end

  end
end
