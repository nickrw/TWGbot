require 'twg/helpers'
require 'twg/plugin'

module TWG
  class Ups < TWG::Plugin
    include Cinch::Plugin

    listen_to :hook_ups_on_battery, :method => :on_battery
    listen_to :hook_ups_off_battery, :method => :off_battery
    listen_to :hook_ups_shutdown, :method => :shutting_down

    def on_battery(m)
      message = "%s is now running on battery power" % bot.nick
      message = append_admins(message)
      message = make_suitably_alarming(message)
      @core.chanm(message)
      hook_async(:hook_shutdown, 0, nil, "requested by UPS")
    end

    def off_battery(m)
      message = "Good news everyone: %s is now back on AC power" % bot.nick
      message = append_admins(message)
      @core.chanm(message)
      hook_async(:hook_openup)
    end

    def shutting_down(m)
      message = "Reserve battery power is now depleted, shutting down"
      message = append_admins(message)
      @core.chanm(message)
      bot.quit("Shutting down as requested by UPS")
      exit
    end

    private

    def make_suitably_alarming(message)
      message = "%s: %s" % [
        Format(:bold, "WARNING"),
        message
      ]
      Format(:red, message)
    end

    def append_admins(message)
      return message if shared[:admins].nil?
      return message if shared[:admins].class != Array
      return message if shared[:admins].empty?
      "%s (fao %s)" % [
        message,
        shared[:admins].join(", ")
      ]
    end

  end
end
