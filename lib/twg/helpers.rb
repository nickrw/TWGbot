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
        shared[:timer] ||= Hash.new
        shared[:timer][method] = Timer(delay, {:shots => 1}) do
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

  end
end
