require 'twg/core'
require 'twg/invite'
require 'twg/seer'
require 'twg/vigilante'

module TWG
  class Loader
    include Cinch::Plugin
    include TWG::Helpers
    listen_to :hook_reload_all, :method => :reload_all
    listen_to :hook_reload_one, :method => :reload_one
    listen_to :hook_unload_one, :method => :unload_one
    listen_to :hook_load_one,   :method => :load_one
    match /(un|re)?load(?: ([^ ]+))?$/, :method => :reload_command
    match /plugins?$/, :method => :list_plugins
    match /plugin ([^ ]+)$/, :method => :toggle_plugin

    def initialize(*args)
      super
      @mine = [
        TWG::Core,
        TWG::Invite,
        TWG::Seer,
        TWG::Vigilante
      ]
      @pluggable = {
        'seer' => TWG::Seer,
        'vigilante' => TWG::Vigilante
      }
      @dir = File.expand_path '..', __FILE__
    end

    def list_plugins(m)
      m.reply "The following TWG plugins are available:"
      @pluggable.each do |pname,klass|
        message = "#{pname}: #{klass.description} "
        if loaded?(klass)
          message += Format(:green, "(enabled)")
        else
          message += Format(:red, "(disabled)")
        end
        m.reply message
      end
      m.reply "Say \"!plugin <name>\" to toggle its state"
    end

    def toggle_plugin(m, plugin)
      if not m.channel?
        m.reply "Toggle plugins in the public channel, not private message"
      end
      if not game_idle?
        m.reply "Cannot load/unload plugins while a game or game signup is in progress"
        return
      end
      klass = @pluggable[plugin]
      if not klass.nil?
        begin
          if loaded?(klass)
            unload_one(klass)
            m.reply "Plugin #{plugin} unloaded"
          else
            load_one(klass)
            m.reply "Plugin #{plugin} loaded"
          end
        rescue => e
          m.reply "Error toggling plugin: #{e.message}"
        end
      else
        m.reply "Plugin '#{plugin}' not found"
      end
    end

    def reload_command(m, type, plugin)
      return if not admin?(m.user)
      if plugin.nil? && type == 're'
        reload_all
        m.reply "Confirm", true
        return
      elsif plugin.nil? && type == 'un'
        unload_all
        m.reply "Confirm", true
        return
      elsif plugin.nil? && type.nil?
        load_all
        m.reply "Confirm", true
        return
      else
        begin
          klass = TWG.const_get(plugin.capitalize)
        rescue NameError
          m.reply "No plugin named #{plugin} found"
          return
        end
        begin
          case type
          when 're'
            if reload_one(klass)
              m.reply "Plugin reloaded: #{plugin}", true
              return
            end
          when 'un'
            if unload_one(klass)
              m.reply "Plugin unloaded: #{plugin}", true
              return
            end
          else
            if load_one(klass)
              m.reply "Plugin loaded: #{plugin}", true
              return
            end
          end
        rescue => e
          m.reply "Error: #{e.message}"
          return
        end
      end
      m.reply "Invalid command", true
    end

    def unload_one(klass)
      i = bot.plugins.find_index { |x| x.class == klass }
      return false if i.nil?
      punload bot.plugins[i]
    end

    def load_one(klass)
      return false if loaded?(klass)
      pload klass
    end

    def reload_one(klass)
      unload_one(klass)
      load_one(klass)
    end

    def reload_all(*args)

      core = nil
      i = bot.plugins.find_index { |x| x.class == TWG::Core }
      if not i.nil?
        core = bot.plugins[i]
      end

      eligable = []
      unloaded = []

      bot.plugins.each do |plugin|
        klass = plugin.class
        next if klass == TWG::Core
        next if not mine?(klass)
        eligable << plugin
        unloaded << klass
      end

      if not core.nil?
        eligable.push(core)
      end
      unloaded.unshift(TWG::Core)

      punload eligable
      pload unloaded

    end

    def unload_all
      all_plugins.each do |plugin|
        unload_one plugin
      end
      unload_one TWG::Core
    end

    def load_all
      pload [TWG::Core] + all_plugins
    end

    private

    def mine?(klass)
      @mine.include?(klass)
    end

    def all_plugins
      mine = @mine.dup
      mine.delete(TWG::Core)
      mine
    end

    def pload(klasses)
      klasses = [klasses] if klasses.class != Array
      klasses.each do |klass|
        if klass.class != Class
          raise ArgumentError, "#pload expects Class or Array[Class]"
        end
        if not mine?(klass)
          raise ArgumentError, "Twg::Loader can't handle plugin of type #{klass}"
        end
        if not loaded?(klass)
          debug "Loading plugin: #{klass}"
          load File.join(@dir, klass.to_s.sub(/^TWG::/,'').downcase + '.rb')
          bot.plugins.register_plugin(klass)
          debug "Loaded plugin: #{klass}"
        else
          debug "Already loaded, noop: #{klass}"
        end
      end
    end

    def punload(plugins)
      plugins = [plugins] if plugins.class != Array
      plugins.each do |plugin|
        klass = plugin.class
        if not mine?(klass)
          raise ArgumentError,"Twg::Loader can't handle plugin of type #{klass}"
        end
        if loaded?(klass)
          debug "Unloading plugin: #{klass}"
          bot.plugins.unregister_plugin(plugin)
          klass.hooks.clear
          klass.matchers.clear
          klass.listeners.clear
          klass.timers.clear
          klass.ctcps.clear
          klass.react_on = :message
          klass.plugin_name = nil
          klass.help = nil
          klass.prefix = nil
          klass.suffix = nil
          klass.required_options.clear
          debug "Unloaded plugin: #{klass}"
        else
          debug "Plugin not loaded, noop: #{klass}"
        end
      end
    end

    def loaded?(klass)
      i = bot.plugins.find_index { |x| x.class == klass }
      not i.nil?
    end

    def game_idle?
      i = bot.plugins.find_index { |x| x.class == TWG::Core }
      return true if i.nil?
      core = bot.plugins[i]
      return true if core.nil?
      return true if core.game.nil?
      return true if core.game.state.nil?
      debug "Game state: #{core.game.state}"
      return false if not [:signup, :wolveswin, :humanswin].include?(core.game.state)
      return false if core.signup_started
      return true
    end

  end
end
