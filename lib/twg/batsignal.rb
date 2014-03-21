require 'twg/plugin'
require 'httparty'
require 'uri'

module TWG
  class Batsignal < TWG::Plugin
    include Cinch::Plugin
    listen_to :hook_signup_started,  :method => :batsignal_on
    listen_to :hook_signup_complete, :method => :batsignal_off
    listen_to :hook_batsignal_on,    :method => :batsignal_on
    listen_to :hook_batsignal_off,   :method => :batsignal_off

    def self.description
      "Lights a signal fire in the real world"
    end

    def initialize(*args)
      super
      commands = @lang.t_array('batsignal.command')
      commands.each do |command|
        command = Regexp.new(command + "(?: +([^ ]+))?$")
        self.class.match(command, :method => :batsignal)
      end
      __register_matchers
      @api = config["api"].sub(/\/$/,'')
      @device = config["device"].to_s
    end

    def batsignal(m, newstate)
      newstate ||= 'on'
      newstate.downcase!
      return if not ['on', 'off'].include?(newstate)
      return if not admin?(m.user)
      turn newstate
    end

    def batsignal_on(m=nil)
      turn 'on'
      hook_async(:hook_batsignal_off, 15)
    end

    def batsignal_off(m=nil)
      turn 'off'
    end

    private

    def state
      call = "%s/%s/%s" % [@api, 'devices', @device]
      r = HTTParty.get(call)
      r.parsed_response["state"]
    end

    def turn(newstate)
      return false if state == newstate
      call = "%s/%s/%s/%s" % [@api, 'devices', @device, newstate]
      debug "Making PUT request to %s" % call
      r = HTTParty.put(call)
      success = r.parsed_response["success"]
      debug "%s API response: %s" % [
        (success ? "Successful" : "Unsuccessful" ),
        r.parsed_response["message"]
      ]
      success
    end

  end
end
