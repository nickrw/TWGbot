require 'twg/plugin'

module TWG
  class Moretime < TWG::Plugin
    include Cinch::Plugin
    listen_to :hook_signup_started, :method => :enable_command
    listen_to :hook_signup_complete, :method => :disable_command

    def self.description
      "Ability to add additional time onto the signup clock"
    end

    def initialize(*args)
      super
      commands = [
        @lang.t_array('moretime.command').map{|c| Regexp.new(c + " ([0-9]+)") },
        @lang.t_array('moretime.command').map{|c| Regexp.new(c + " ?$") }
      ]
      commands.flatten!
      commands.each do |command|
      self.class.match(command, :method => :moretime)
      end
      __register_matchers
      @signup = @coreconfig["game_timers"]["registration"]
      @additional = config["seconds"] ||= 120
      @added = 0
      disable_command
    end

    def moretime(m, seconds=nil)

      # The :hook_signup_started hook will assign @when a Time object, so we can
      # calculate the number of seconds elapsed when !moretime is called.
      #
      # We can ignore the request entirely if @when isn't a Time object as
      # that means no signup is in progress.
      return if not @when.class == Time

      # seconds will be nil if !moretime is triggered without an argument
      # use the cinchize configuration value 'seconds' (@additional) in
      # that case.
      if seconds.nil?
        seconds = @additional
        seconds = @limit if seconds > @limit
      end

      # seconds will be passed a string (regex match)
      seconds = seconds.to_i

      # If we have reached the registration increase limit or someone is
      # trying a silly number to make the bot unusable, say so.
      if @limit < 1 or seconds > @limit
        m.reply(@lang.t('moretime.toohigh', :limit => @signup), true)
        return
      end

      # maintain a dignified silence if negative numbers are tried
      return if seconds < 1

      # keep a running total of added time
      @added += seconds

      # Cancel the game registration window timers and re-set them with the
      # extra seconds
      hook_cancel(:ten_seconds_left)
      hook_cancel(:hook_signup_complete)
      @limit = @limit - seconds
      remaining = @signup - (Time.now - @when).to_i
      hook_async(:ten_seconds_left, remaining + @added - 10)
      hook_async(:hook_signup_complete, remaining + @added)
      m.reply(@lang.t('moretime.confirm', :count => seconds), true)
    end

    def enable_command(m=nil)
      @limit = @signup
      @added = 0
      @when = Time.now
    end

    def disable_command(m=nil)
      @when = nil
    end

  end
end
