require 'twg/core'
require 'twg/helpers'

module TWG
  class Plugin
    include ::Cinch::Plugin
    include ::TWG::Helpers

    def initialize(*args)
      super
      i = bot.plugins.find_index { |x| x.class == TWG::Core }
      @core = bot.plugins[i]
      @coreconfig = @core.coreconfig
      @game = @core.game
      @lang = @core.lang
      debug "Found core at bot.plugins[#{i}] (#{@core.class})"
    end

    def chansay(translation, args = nil)
      @core.chanm(@lang.t(translation, args))
    end

  end

  # This exception can be raised when a plugin wants its *parent* thread to
  # exit. This should be used in methods which expected to be executed via 
  # hook_sync only.
  class PluginOverrideException < Exception ; end

end
