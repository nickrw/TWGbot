require 'i18n'

module TWG
  class LangException < I18n::ExceptionHandler
    def call(exception, locale, key, options)
      if exception.is_a?(I18n::MissingTranslation)
        raise exception.to_exception
      else
        super
      end
    end
  end
end
