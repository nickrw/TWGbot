{
  :default => {
    :lang => {

      # twg.active: true/false - whether the language is loadable
      :active => true,
      # Example to only activate the language pack if the month is December
      # :active => lambda { |key,opts| Time.now.month == 12 },

      # twg.listed: true/false - show the language pack in the !langs list?
      :listed => true,

    }
  }
}
