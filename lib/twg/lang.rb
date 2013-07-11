require 'i18n'
require 'i18n/backend/pluralization'
require 'twg/langexception'

module TWG

  class Lang

    attr_reader :pack

    def initialize(pack = :default)
      @gemroot = File.expand_path '../../..', __FILE__
      I18n.default_locale = :default
      I18n.exception_handler = TWG::LangException.new
      I18n::Backend::Simple.send(:include, I18n::Backend::Pluralization)
      select pack
    end

    def select(pack)
      locs = list
      return nil if not locs.keys.include?(pack)
      @pack = pack
      I18n.locale = pack
      locs[pack]
    end

    def list
      I18n.load_path = Dir[File.join(@gemroot, 'lang', '*.{yml,rb}')]
      locs = {}
      I18n.available_locales.each do |loc|
        begin
          desc = I18n.translate 'description', :locale => loc
        rescue I18n::MissingTranslationData
          next
        end
        locs[loc] = desc
      end
      locs
    end

    def t(key, kwargs={})

      begin
        tr = I18n.translate key, kwargs.merge({:locale => @pack})
      rescue I18n::MissingInterpolationArgument => e
        return "Translation error: #{e.message}"
      end

      case tr
      when String
        return tr
      when Array
        begin
          # I18n doesn't interpolate if key returns an array
          # Pick a random array element and interpolate it.
          return I18n.interpolate(tr.shuffle.first, kwargs)
        rescue I18n::MissingInterpolationArgument => e
          return "Translation error: #{e.message}"
        end
      else
        return "Translation error: unexpected class returned: #{tr.class}"
      end

    end

  end

end
