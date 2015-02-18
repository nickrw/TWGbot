{
  :default => {
    :lang => {

      # twg.active: true/false - whether the language is loadable
      :active => true,
      # Example to only activate the language pack if the month is December
      # :active => lambda { |key,opts| Time.now.month == 12 },

      # twg.listed: true/false - show the language pack in the !langs list?
      :listed => true,

    },
    :vote => {
      :day => {
        :vote => lambda { |key, opts|
          # Easter egg vote string. 1 in 200 chance of firing.
          if rand(200) == 100
            opts[:voter].upcase + " WILL END " + opts[:votee].upcase
          else
            if opts[:voter] == "CapnJosh" and rand(10) == 5
              opts[:voter] + " vote's for " + opts[:votee]
            else 
              opts[:voter] + " voted for " + opts[:votee]
            end
          end
        }
      }
    }
  }
}
