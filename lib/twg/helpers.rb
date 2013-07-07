module TWG
  module Helpers

    def players_of_role(role = :normal, invert = false)
      a = []
      @game.participants.each do |player, r|
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

    def pick_special(role, default_odds=5)
      synchronize(:pick_special) do
        p = players_of_role(:normal)
        odds_per_player = config["odds_per_player"]
        odds_per_player ||= default_odds
        odds = p.count * odds_per_player
        info "Picking #{role.to_s}, with #{odds}% chance of success. #{odds_per_player}% * #{p.count} normal players)"
        r = rand(100)
        if r <= odds
          s = p.shuffle[0]
          @game.participants[s] = role
          info "Selected player: #{s} (#{r} <= #{odds})"
        else
          info "No player selected (#{r} > #{odds})"
        end
      end
    end

    def hook_raise(method, async=true, m=nil, *args)
      info "Calling #{async ? 'async' : 'sync'} hook: #{method.to_s}"
      ta = bot.handlers.dispatch(method, m, *args)
      info "Hooked threads for #{method.to_s}: #{ta}"
      return ta if async
      return ta if not ta.respond_to?(:each)
      info "Joining threads for #{method.to_s}"
      ta.each do |thread|
        begin
          thread.join
        rescue => e
          debug e.inspect
        end
      end
      info "Hooked threads for #{method.to_s} complete"
      ta
    end

    def hook_async(method, delay=0, m=nil, *args)
      if delay == 0
        hook_raise(method, true, m, *args)
      else
        tconfig = {
          :shots => 1,
          :start_automatically => false
        }
        shared[:timer] ||= Hash.new
        shared[:timer][method] = Timer(delay, tconfig) do
          hook_raise(method, true, m, *args)
          shared[:timer][method] = nil
        end
      end
    end

    def hook_sync(method, m=nil, *args)
      hook_raise(method, false, m, *args)
    end

    def hook_cancel(method, run = false)
      info "Cancelling timer for hook #{method}"
      shared[:timer] ||= Hash.new
      t = shared[:timer][method]
      shared[:timer][method] = nil
      return if t.nil?
      return if t.stopped?
      t.stop
      return if not run
      info "Scheduling immediate execution of cancelled hook #{method}"
      t.interval = 0
      t.shots = 1
      t.start
    end

    def hook_expedite(method)
      hook_cancel(method, true)
    end

    def clean(str)
      if str.class != String
        raise ArgumentError, "Non-string variable passed to clean"
      end
      str = Cinch::Utilities::String.filter_string(str)
      str.strip
    end

    def ratelimit(id, limit)
      if id.class != Symbol
        raise ArgumentError, "id should be a Symbol"
      end
      if limit.class != Fixnum
        raise ArgumentError, "limit should be Fixnum"
      end

      now = Time.now.to_i
      shared[:ratelimit] ||= Hash.new
      shared[:ratelimit][id] ||= 0

      difference = now - shared[:ratelimit][id]
      if difference < limit
        return (limit - difference)
      end

      shared[:ratelimit][id] = now
      return 0
    end

    def admin?(user)
      user.refresh
      shared[:admins].include?(user.authname)
    end

  end
end
