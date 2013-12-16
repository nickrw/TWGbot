require 'i18n'
require 'i18n/backend/pluralization'
require 'twg/langexception'

module TWG

  class Lang

    attr_reader :pack
    @@gemroot = File.expand_path '../../..', __FILE__

    def initialize(pack = :default, fallback = :default)
      @fallback = fallback
      select pack
    end

    def self.reload
      I18n.reload!
      I18n.default_locale = :default
      I18n.load_path = Dir[File.join(@@gemroot, 'lang', '*.{yml,rb}')]
      I18n.exception_handler = TWG::LangException.new
      I18n::Backend::Simple.send(:include, I18n::Backend::Pluralization)
    end

    def self.list
      self.reload
      packs = {}
      I18n.available_locales.each do |pack|

        begin
          # Skip this language pack from the list if it is 
          next if (I18n.translate 'lang.listed', :locale => pack) == false
        rescue I18n::MissingTranslationData
          # We don't care about 'listed' not being included in a language pack
          # and default to including the pack in the list if this is missing.
        end

        begin
          packs[pack] = I18n.translate 'lang.description', :locale => pack
        rescue I18n::MissingTranslationData
          packs[pack] = '???'
        end

      end
      packs
    end

    def select(pack)

      self.class.reload
      return :notfound if not I18n.available_locales.include?(pack)

      begin
        return :inactive if (I18n.translate 'lang.active', :locale => pack) == false
      rescue I18n::MissingTranslationData
        # Language pack doesn't include a lang.active key, which is
        # assumed to mean it doesn't care and always wants to be active
      end

      @pack = pack
      I18n.locale = pack
      true

    end

    def t(key, kwargs={})

      tr = safe_translate(key, kwargs.merge({:locale => @pack}))

      # The lang.* keys are used internally, return it immediately
      # without trying to do something special based on its class
      return tr if key.to_s =~ /^lang\./

      # For all other keys, figure out if further processing is required
      # or just return the translation we calculated.
      case tr

      # Strings are easy
      when String
        return tr

      # I18n doesn't interpolate if key returns an array
      # Pick a random array element and interpolate it.
      when Array
        random_tr = tr.shuffle.first
        # We really only want to be dealing with strings at this point,
        # because if you're trying to do recursion here you're
        # definitely doing it wrong. Use a damn lambda instead.
        if random_tr.class != String
          return "Translation error: unexpected class when passing Array entry for interpolation: #{random_tr.class}"
        else
          begin
            return I18n.interpolate(random_tr, kwargs)
          rescue I18n::MissingInterpolationArgument => e
            return "Translation error: #{e.message}"
          end
        end

      # TWG core only ever expect a String in response.
      else
        return "Translation error: unexpected class returned: #{tr.class}"
      end

    end

    private

    def safe_translate(key, kwargs={})
      kwargs[:locale] ||= @fallback
      begin
        tr = I18n.translate key, kwargs
        return tr
      rescue I18n::MissingTranslationData => e
        if kwargs[:locale] != @fallback
          kwargs[:locale] = @fallback
          return safe_translate(key, kwargs)
        else
          return "Translation error: #{e.message}"
        end
      rescue I18n::MissingInterpolationArgument => e
        return "Translation error: #{e.message}"
      end
    end

  end

end
