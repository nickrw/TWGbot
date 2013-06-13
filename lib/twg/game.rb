module TWG
  class Game
    
    attr_reader :participants
    attr_reader :state
    attr_reader :live_wolves
    attr_reader :live_norms
    attr_reader :votes
    attr_reader :voted
    attr_reader :game_wolves
    attr_reader :min_part
    attr_reader :iteration
    attr_reader :seer
    attr_accessor :enable_seer

    def initialize(debug=false)
      reset
      @enable_seer = false
      @debug = debug
    end

    def reset
      @state = :signup
      @iteration = 0
      @participants = {}
      @min_part = 6
      @wolf_ratio = (1.0/5.0)
      @game_wolves = []
      @live_wolves = 0
      @live_norms = 0
      @seer = ""
      @seetarget = ""
      @votes = {}
      @voted = []
    end
    
    def start
      if @participants.length >= @min_part
        assign_roles
        start = Haps.new(:action => :channel, :code => :gamestart, :message => "Game started!")
        @state = :night
        @iteration = 1
        state_transition_in
        return start
      else
        @state = nil
        return Haps.new(:action => :channel, :code => :notenoughplayers, :message => "Not enough players to start game: #{@participants.length}/#{@min_part}")
      end
    end
    
    def register(nick)
      if @state == :signup
        unless @participants.keys.include?(nick)
          @participants.merge!({nick => :normal})
          return Haps.new(:action => :channel, :code => :confirmplayer, :message => "#{nick} registered successfully")
        else
          return Haps.new(:action => :channel, :code => :alreadyplayer, :message => "#{nick} already registered")
        end
      else
        return Haps.new(:action => :none, :code => :unregisterablestate, :message => "Can't register during #{@state}")
      end
    end

    def nickchange(oldnick, newnick)

      # replace player
      role = @participants.delete(oldnick)
      @participants.merge!({newnick => role})

      # Change special characters
      if @game_wolves.include?(oldnick)
        @game_wolves.delete(oldnick)
        @game_wolves << newnick
      end
      if @seetarget == oldnick
        @seetarget = newnick
      end
      if @seer == oldnick
        @seer = newnick
      end

      # Replace votes for and by the player
      tvoted = @voted.dup
      tvoted.each do |voter,votee|
        if votee == oldnick
          record_vote(voter,newnick)
        end
        if voter == oldnick
          @voted[newnick] = votee
          @voted.delete(oldnick)
        end
      end
      tvoted = nil

      # Tidy up the vote count for the old nick. This should be zero
      # as looping through and using record_vote on the voted hash should
      # have decremented it.
      if @votes.keys.include?(oldnick)
        @votes.delete(oldnick)
      end

    end

    # Advances the game to the next state
    def next_state
      newstate = state_transition_out
      newiteration = @iteration
      if [:day, :signup].include?(@state)
        newiteration = @iteration + 1
      end
      @state = newstate
      @iteration = newiteration
      #state_transition_in
      @state
    end

    # Receives and process a vote from the outside world
    def vote(nick,vfor,type)
      voter_is = @participants[nick]
      votee_is = @participants[vfor]
      act = {:night => :nick, :day => :reply}
      return Haps.new(:action => :none, :code => :notvotablestate, :state => @state, :message => "#{nick} tried to vote for #{vfor} during #{@state}") unless [:day, :night].include?(@state)
      if ((@state == :night) && (type == :channel) || ((@state == :day) && (type == :private)))
        return Haps.new(:action => :none, :code => :illegalvotetype, :state => @state, :message => "#{nick} tried a #{type} vote during #{@state}") 
      end
      return Haps.new(:action => :none, :code => :voternotplayer, :state => @state, :message => "#{nick} tried to vote but isn't playing") unless player?(nick)
      return Haps.new(:action => :none, :code => :voterdead, :state => @state, :message => "#{nick} is dead but tried to vote for #{vfor}") if dead?(nick)
      return Haps.new(:action => :reply, :code => :voteself, :state => @state, :message => "#{nick} tried to vote for themselves") if nick == vfor
      return Haps.new(:action => :reply, :code => :voteenotplayer, :state => @state, :message => "#{nick} tried to vote for non-player: #{vfor}") unless player?(vfor)
      return Haps.new(:action => :reply, :code => :voteedead, :state => @state, :message => "#{nick} tried to vote for dead player: #{vfor}") if dead?(vfor)
      if @state == :night
        return Haps.new(:action => :reply, :code => :notawolf, :state => @state, :message => "#{nick} is not a wolf but tried to vote at night") unless @game_wolves.include?(nick)
        return Haps.new(:action => :reply, :code => :fellowwolf, :state => @state, :message => "#{nick} tried to vote for fellow wolf #{vfor}") if @game_wolves.include?(vfor)
      end
      if @voted.include?(nick)
        record_vote(nick,vfor)
        return Haps.new(:action => :reply, :code => :changedvote, :state => @state, :message => "#{nick} changed their vote to #{vfor}") 
      else
        record_vote(nick,vfor)
        return Haps.new(:action => :reply, :code => :confirmvote, :state => @state, :message => "#{nick} voted for #{vfor}")
      end
    end
    
    def see(user, target)
      return Haps.new(:action => :private, :code => :notnight, :state => @state, :message => "#{user} tried to see #{target} during #{@state}") if @state != :night
      return Haps.new(:action => :private, :code => :nottheseer, :state => @state, :message => "#{user} tried to see #{target} but is not the seer") if user != @seer
      return Haps.new(:action => :private, :code => :alreadyseen, :state => @state, :message => "The seer, #{user}, tried to see #{target} but has already seen in this iteration.") unless @seetarget.empty?
      return Haps.new(:action => :private, :code => :seerdead, :state => @state, :message => "The seer, #{user}, tried to see #{target}, but the seer is dead.") if @participants[user] == :dead
      return Haps.new(:action => :private, :code => :targetnotplayer, :state => @state, :message => "#{user} tried to see #{target}, which is not a player.") if !player?(target)
      return Haps.new(:action => :private, :code => :targetdead, :state => @state, :message => "The seer, #{user}, tried to see #{target}, but the target is dead.") if @participants[target] == :dead
      return Haps.new(:action => :private, :code => :seerself, :state => @state, :message => "The seer, #{user}, tried to see themselves.") if target == user
      @seetarget = target
      return Haps.new(:action => :private, :code => :confirmsee, :state => @state, :message => "The seer, #{user}, selected a target: #{target}.")
    end
    
    def reveal
      return Haps.new(:action => :private, :code => :notarget, :state => @state, :message => "No target to see") if @seetarget.empty?
      return Haps.new(:action => :private, :code => :targetkilled, :target => @seetarget, :state => @state, :message => "The seer's target was killed during the night") if @participants[@seetarget] == :dead
      return Haps.new(:action => :private, :code => :youkilled, :target => @seetarget, :state => @state, :message => "The seer was killed during the night") if @participants[@seer] == :dead
      return Haps.new(:action => :private, :code => :sawwolf, :target => @seetarget, :state => @state, :message => "The seer's target was a wolf!") if @participants[@seetarget] == :wolf
      return Haps.new(:action => :private, :code => :sawhuman, :target => @seetarget, :state => @state, :message => "The seer's target was a human") if @participants[@seetarget].class == Symbol
    end

    def wolves_alive
      alive = []
      @game_wolves.each do |wolf|
        alive << wolf if alive?(wolf)
      end
      alive
    end

    def check_victory_condition
      return :wolveswin if (@state == :day) && (@live_wolves >= (@live_norms - 1))
      return :humanswin if @live_wolves == 0
      return nil
    end

    def state_transition_in
      clear_votes
    end

    def state_transition_out
      return @state if [:humanswin, :wolveswin].include?(@state)
      victory = check_victory_condition
      if not victory.nil?
        victory
      elsif [:day, :signup].include?(@state)
        :night
      elsif @state == :night
        :day
      else
        @state
      end
    end

    def record_vote(nick,vfor)
      if @voted[nick] and not @votes[@voted[nick]].nil?
        @votes[@voted[nick]] -= 1
      end
      @voted[nick] = vfor
      if @votes[vfor].nil?
        @votes[vfor] = 1
      else
        @votes[vfor] += 1
      end
    end

    def clear_votes
      @voted = {}
      @votes = {}
      @seetarget = ""
    end

    def assign_roles
      
      # Convert all keys in @participants to strings, to make comparison (voting, etc) easier.
      # These will initially be Cinch::User objects for IRC.
      partasstring = {}
      @participants.keys.each { |part| partasstring[part.to_s] = :normal }
      @participants = partasstring
      
      @live_wolves = (@wolf_ratio * @participants.length).to_i
      @live_norms = @participants.length - @live_wolves
      @game_wolves = @participants.keys.shuffle[0..(@live_wolves-1)].sort

      @game_wolves.each do |wolf|
        @participants[wolf] = :wolf
      end
      
      if @enable_seer
        @seer = @participants.keys.shuffle[0]
        if not @game_wolves.include? @seer
          @participants[@seer] = :seer
        else
          @seer = nil
        end
      end
      
    end

    def apply_votes
      highest = 0
      tiebreak = []
      @votes.each do |votee, count|
        if count > highest
          tiebreak = [votee]
          highest = count
        elsif count == highest
          tiebreak << votee
        end
      end
      killme = nil
      if tiebreak.length > 1
        killme = tiebreak[rand(tiebreak.length)]
      elsif tiebreak.length == 1
        killme = tiebreak[0]
      end
      return Haps.new(:action => :channel, :code => :novotes, :state => @state, :message => "No votes were made!") if killme.nil?
      was = kill(killme)
      case was
        when :wolf
          return Haps.new(:action => :channel, :code => :wolfkilled, :killed => killme, :state => @state, :message => "#{killme} has been killed at popular request")
        else 
          return Haps.new(:action => :channel, :code => :normkilled, :killed => killme, :state => @state, :message => "#{killme} has been killed at popular request")
      end
    end

    def kill(target)
      role = @participants[target]
      return nil if role.nil?
      @participants[target] = :dead
      case role
      when :wolf
        @live_wolves -= 1
      else
        @live_norms -= 1
      end
      role
    end

    def player?(name)
      @participants.keys.include?(name)
    end

    def wolf?(name)
      @game_wolves.include(name)
    end

    def alive?(name)
      return false unless player?(name)
      @participants[name] != :dead
    end

    def dead?(name)
      !alive?(name)
    end

  end

  class Haps
    attr_reader :action
    attr_reader :recipient
    attr_reader :code
    attr_reader :message
    attr_reader :opts
    def initialize(opts)
      @opts = opts
      @action = opts[:action]
      @recipient = opts[:recipient]
      @code = opts[:code]
      @message = opts[:message]
      puts self.inspect
    end

  end
end

