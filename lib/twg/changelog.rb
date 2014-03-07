require 'twg/helpers'
require 'twg/plugin'

module TWG
  class Changelog < TWG::Plugin
    include Cinch::Plugin

    def initialize(*args)
      super
      commands = @lang.t_array('changelog.command')
      commands.each do |command|
        self.class.match(command, :method => :changelog)
      end
      __register_matchers
    end

    def changelog(m)
      m.reply("https://github.com/nickrw/TWGbot/commits/master", true)
    end

  end
end
