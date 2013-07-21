require 'i18n'

module TWG
  class LangException < I18n::ExceptionHandler
    def call(exception, locale, key, options)
      if exception.is_a?(I18n::MissingTranslation) && key.to_s != 'i18n.plural.rule'
        raise exception.to_exception
      else
        super
      end
    end
  end
end
