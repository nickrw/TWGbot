module TWG
  class IRC
    class Seer
      include Cinch::Plugin
      listen_to :notify_roles, :method => :notify_roles
      listen_to :enter_night, :method => :solicit_seer_choice
      listen_to :seer_reveal, :method => :seer_reveal
      match /see ([^ ]+)$/, :method => :see
  
      def initialize(*args)
        super
        shared[:game].enable_seer = true
      end
  
      def solicit_seer_choice(m)
        return if shared[:game].nil?
        if shared[:game].seer && shared[:game].participants[shared[:game].seer] != :dead
          User(shared[:game].seer).send "It is now NIGHT %s: say !see <nickname> to me to reveal their role." % shared[:game].iteration.to_s
        end
      end
      
      def seer_reveal(m, r = nil)
        return if shared[:game].nil?
        unless r.nil?
          case r.code
            when :targetkilled
              User(shared[:game].seer).send "You snuck up to %s's desk to see if you got sniffles, but find their dead body. An ugly dog got there before you." % r.opts[:target]
            when :youkilled
              User(shared[:game].seer).send "While you are sneaking about at night trying to find the culprit you stumble across an ugly dog. Uh oh, you're dead." % r.opts[:target]
            when :sawwolf
              User(shared[:game].seer).send "As soon as you got anywhere near %s you started sneezing uncontrollably! Looks like you found an UGLY DOG." % r.opts[:target]
            when :sawhuman
              User(shared[:game].seer).send "You don't have any reaction to %s - looks like %s is a fellow wage slave." % [r.opts[:target], r.opts[:target]]
          end
        end
      end
  
      def notify_roles(m)
        return if shared[:game].nil?
        User(shared[:game].seer).send "You are the SEER. You are allergic to dogs, giving you a natural ability to sense their presence." if shared[:game].seer
      end
  
      def see(m, target)
        if shared[:game] && m.channel? == false
          r = shared[:game].see(m.user.nick, target)
          case r.code
            when :confirmsee
              m.reply "#{target}'s identity will be revealed to you as you wake."
            when :seerself
              m.reply "You'd probably notice if you were the ugly dog"
            when :targetdead
              m.reply "#{target} is dead, try again."
            when :alreadyseen
              m.reply "You have already chosen tonight."
          end
        end
      end
    end
  end
end
