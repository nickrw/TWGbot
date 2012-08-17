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
              User(shared[:game].seer).send "You have a vision of %s's body, twisted, broken and bloody. A wolf got there before you." % r.opts[:target]
            when :youkilled
              User(shared[:game].seer).send "While dreaming vividly about %s you get viciously torn to pieces. Your magic 8 ball didn't see that one coming!" % r.opts[:target]
            when :sawwolf
              User(shared[:game].seer).send "You have a vivid dream about %s wearing a new fur coat. You've found a WOLF." % r.opts[:target]
            when :sawhuman
              User(shared[:game].seer).send "You have a dull dream about %s lying in bed, dreaming. It looks like %s is a fellow villager." % [r.opts[:target], r.opts[:target]]
          end
        end
      end
  
      def notify_roles(m)
        return if shared[:game].nil?
        User(shared[:game].seer).send "You are the SEER. Each night you can have the role of a player of your choice revealed. Choose carefully, once the inner eye has selected a target it cannot be swayed." if shared[:game].seer
      end
  
      def see(m, target)
        if shared[:game] && m.channel? == false
          r = shared[:game].see(m.user.nick, target)
          case r.code
            when :confirmsee
              m.reply "#{target}'s identity will be revealed to you as you wake."
            when :seerself
              m.reply "Surely you know what you are... try again."
            when :targetdead
              m.reply "#{target} is dead, try again."
            when :alreadyseen
              m.reply "You have already selected tonight's vision!"
          end
        end
      end
    end
  end
end