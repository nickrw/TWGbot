require 'twg/core'

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
      @pluggable = ['seer', 'vigilante', 'witch']
      @dir = File.expand_path '..', __FILE__
    end

    def list_plugins(m)
      m.reply "The following TWG plugins are available:"
      @pluggable.each do |pname|
        klass = name2klass(pname)
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
        return
      end
      if not game_idle?
        m.reply "Cannot load/unload plugins while a game or game signup is in progress"
        return
      end
      klass = nil
      plugin.downcase!
      if @pluggable.include?(plugin)
        klass = name2klass(plugin)
        debug "Identified plugin class to toggle: #{klass.to_s}"
      end
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
        pload TWG::Core
        m.reply "Confirm", true
        return
      else
        begin
          klass = name2klass(plugin)
        rescue
          m.reply "No plugin named #{plugin} found"
          return
        end
        debug klass.to_s
        begin
          case type
          when 're'
            if reload_one(klass)
              m.reply "Plugin reloaded: #{plugin}", true
              return
            end
          when 'un'
            if klass == TWG::Loader
              m.reply "Cannot unload the Loader plugin"
              return
            end
            if unload_one(klass)
              m.reply "Plugin unloaded: #{plugin}", true
            else
              m.reply "Unable to unload plugin: #{plugin}", true
            end
            return
          else
            if load_one(klass)
              m.reply "Plugin loaded: #{plugin}", true
            else
              m.reply "Plugin already loaded: #{plugin}", true
            end
            return
          end
        rescue => e
          m.reply "Error: #{e.message}"
          debug e.backtrace
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
      kstr = klass
      unload_one(klass)
      klass = load_plugin_from_file(kstr)
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
        next if klass == TWG::Loader
        next if not mine?(klass)
        eligable << plugin
        unloaded << klass
      end

      if not core.nil?
        eligable.push(core)
      end

      punload eligable
      unloaded.unshift(TWG::Core)

      fake_plugins = [TWG::Plugin, TWG::Lang, TWG::LangException, TWG::Game, TWG::Helpers]
      other_constants = []

      TWG.constants.each do |constant|
        c = TWG.const_get(constant)
        next if unloaded.include?(c)
        next if fake_plugins.include?(c)
        next if c == TWG::Loader
        other_constants << c
      end

      fake_plugins_str = []
      fake_plugins.each { |pl| fake_plugins_str << pl.to_s }
      fake_plugins_str.reverse!
      unloaded.each { |pl| fake_plugins_str << pl.to_s }
      other_constants_str = []
      other_constants.each { |pl| other_constants_str << pl.to_s }
      other_constants_str.reverse!
      destroy_plugin(unloaded)
      destroy_plugin(other_constants)
      destroy_plugin(fake_plugins)
      begin
        load_plugin_from_file(fake_plugins_str)
        load_plugin_from_file(other_constants_str)
      rescue ArgumentError
      end

      pload unloaded

    end

    # Unloads all TWG:: plugins, except the Loader
    def unload_all
      @last_unload = []
      loaded_safe.each do |plugin|
        unload_one plugin
        @last_unload << plugin
      end
      unload_one TWG::Core
    end

    private

    def name2klass(plugin_name)
      plugin_name.strip!
      if plugin_name =~ /^TWG::/
        plugin_fq = plugin_name
        plugin = plugin_name.sub(/^TWG::/,'').capitalize
      else
        plugin_fq = 'TWG::' + plugin_name.capitalize
        plugin = plugin_name.capitalize
      end
      begin
        TWG.const_get(plugin)
      rescue
        debug "Couldn't find object: #{plugin_fq}"
        load_plugin_from_file(plugin_fq)
      end
    end

    def load_plugin_from_file(klass)
      if klass.class == Array
        klass.each { |kl| load_plugin_from_file(kl) }
        return
      end
      if klass.class != String
        klass_string = klass.to_s
      else
        klass_string = klass
      end
      constpart = klass_string.sub(/^TWG::/,'')
      filepart = constpart.downcase
      filename = File.join(@dir, filepart + '.rb')
      debug "Loading file: #{filename}"
      if not File.exist?(filename)
        raise ArgumentError, "Plugin does not exist"
      end
      load filename
      TWG.const_get(constpart)
    end

    def destroy_plugin(klass)
      if klass.class == Array
        klass.each { |kl| destroy_plugin(kl) }
      else
        # FIXME
        # Blacklist TWG::Core from being destroyed as it would break
        # config options given through cinchize, and the @@lang class variable
        # on the core would be forgotten, rendering TWG::Loader useless for
        # reloading all the plugins when the language changes.
        #
        # Perhaps this should be broken out into a TWG::Config plugin which the
        # loader can't touch?
        return true if klass == TWG::Core
        const = klass.to_s.sub(/^TWG::/, '').to_sym
        TWG.__send__(:remove_const, const)
        debug "Destroyed plugin object: TWG::#{const}"
      end
    end

    def loaded
      plugins = []
      bot.plugins.each do |pl|
        plugins << pl.class if pl.class.to_s =~ /^TWG::/
      end
      plugins
    end

    def mine?(klass)
      loaded.include?(klass)
    end

    def loaded_safe
      mine = loaded
      mine.delete(TWG::Core)
      mine.delete(TWG::Loader)
      mine
    end

    def pload(klasses)
      klasses = [klasses] if klasses.class != Array
      klasses.each do |klass|
        if klass.class == String
          klass = name2klass(klass)
        end
        if klass.class != Class
          raise ArgumentError, "#pload expects Class or Array[Class]"
        end
        if not loaded?(klass)
          debug "Loading plugin: #{klass}"
          rklass = load_plugin_from_file(klass)
          bot.plugins.register_plugin(rklass)
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
        if loaded?(klass)
          debug "Unloading plugin: #{klass}"
          bot.plugins.unregister_plugin(plugin)
          if klass == TWG::Loader
            kstr = klass.to_s
            destroy_plugin(klass)
            klass = kstr
          else
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
          end
          debug "Unloaded plugin: #{klass}"
        else
          debug "Plugin not loaded, noop: #{klass}"
        end
      end
    end

    def loaded?(klass)
      loaded.include?(klass)
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
