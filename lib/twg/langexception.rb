require 'i18n'

module TWG
  class LangException < I18n::ExceptionHandler
    def call(exception, locale, key, options)
      if exception.is_a?(I18n::MissingTranslation)
        if key == 'description'
          raise exception.to_exception
        else
          super
        end
      else
        super
      end
    end
  end
end
