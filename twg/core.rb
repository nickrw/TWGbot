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
      role = @participants.delete(oldnick)
      @participants.merge!({newnick => role})
      if @game_wolves.include?(oldnick)
        @game_wolves.delete(oldnick)
        @game_wolves << newnick
      end
      if @voted.include?(oldnick)
        @voted.delete(oldnick)
        @voted << newnick
      end
      if @votes.keys.include?(oldnick)
        count = @votes.delete(oldnick)
        @votes.merge!({newnick => count})
      end
    end

    # Advances the game to the next state (and returns the action taken when exiting current state)
    def next_state
      newstate, r = state_transition_out
      newiteration = @iteration
      if [:day, :signup].include?(@state)
        newiteration = @iteration + 1
      end
      @state = newstate
      @iteration = newiteration
      #state_transition_in
      r
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
      return Haps.new(:action => :reply, :code => :alreadyvoted, :state => @state, :message => "#{nick} has already voted but tried to vote for #{vfor}") if @voted.include?(nick)
      return Haps.new(:action => :reply, :code => :voteself, :state => @state, :message => "#{nick} tried to vote for themselves") if nick == vfor
      return Haps.new(:action => :reply, :code => :voteenotplayer, :state => @state, :message => "#{nick} tried to vote for non-player: #{vfor}") unless player?(vfor)
      return Haps.new(:action => :reply, :code => :voteedead, :state => @state, :message => "#{nick} tried to vote for dead player: #{vfor}") if dead?(vfor)
      if @state == :night
        return Haps.new(:action => :reply, :code => :notawolf, :state => @state, :message => "#{nick} is not a wolf but tried to vote at night") unless @game_wolves.include?(nick)
        return Haps.new(:action => :reply, :code => :fellowwolf, :state => @state, :message => "#{nick} tried to vote for fellow wolf #{vfor}") if @game_wolves.include?(vfor)
      end
      record_vote(nick,vfor)
      return Haps.new(:action => :reply, :code => :confirmvote, :state => @state, :message => "#{nick} voted for #{vfor}")
    end
    
    def see(user, target)
      return Haps.new(:action => :private, :code => :notnight, :state => @state, :message => "#{user} tried to see #{target} during #{@state}") if @state != :night
      return Haps.new(:action => :private, :code => :nottheseer, :state => @state, :message => "#{user} tried to see #{target} but is not the seer") if user != @seer
      return Haps.new(:action => :private, :code => :alreadyseen, :state => @state, :message => "The seer, #{user}, tried to see #{target} but has already seen in this iteration.") unless @seetarget.empty?
      return Haps.new(:action => :private, :code => :seerdead, :state => @state, :message => "The seer, #{user}, tried to see #{target}, but the seer is dead.") if @participants[user] == :dead
      return Haps.new(:action => :private, :code => :targetnotplayer, :state => @state, :message => "#{user} tried to see #{target}, which is not a player.") if !player?(target)
      return Haps.new(:action => :private, :code => :targetdead, :state => @state, :message => "The seer, #{user}, tried to see #{target}, but the target is dead.") if @participants[target] == :dead
      return Haps.new(:action => :private, :code => :seerself, :state => @state, :message => "The seer, #{user}, tried to see themselves.") if @participants[target] == :dead
      @seetarget = target
      return Haps.new(:action => :private, :code => :confirmsee, :state => @state, :message => "The seer, #{user}, selected a target: #{target}.")
    end
    
    def reveal
      return Haps.new(:action => :private, :code => :notarget, :state => @state, :message => "No target to see") if @seetarget.empty?
      return Haps.new(:action => :private, :code => :targetkilled, :target => @seetarget, :state => @state, :message => "The seer's target was killed during the night") if @participants[@seetarget] == :dead
      return Haps.new(:action => :private, :code => :youkilled, :target => @seetarget, :state => @state, :message => "The seer was killed during the night") if @participants[@seer] == :dead
      return Haps.new(:action => :private, :code => :sawwolf, :target => @seetarget, :state => @state, :message => "The seer's target was a wolf!") if @participants[@seetarget] == :wolf
      return Haps.new(:action => :private, :code => :sawhuman, :target => @seetarget, :state => @state, :message => "The seer's target was a human") if @participants[@seetarget] == :normal
    end

    def wolves_alive
      alive = []
      @game_wolves.each do |wolf|
        alive << wolf if alive?(wolf)
      end
      alive
    end

    def state_transition_in
      clear_votes
    end

    def state_transition_out
      return [@state, @state] if [:humanswin, :wolveswin].include?(@state)
      r = apply_votes
      if (@state == :day) && (@live_wolves >= (@live_norms - 1))
        [:wolveswin, r]
      elsif @live_wolves == 0
        [:humanswin, r]
      elsif [:day, :signup].include?(@state)
        [:night, r]
      elsif @state == :night
        [:day, r]
      else
        [@state, r]
      end
    end

    private

    def record_vote(nick,vfor)
      @voted << nick
      if @votes[vfor].nil?
        @votes[vfor] = 1
      else
        @votes[vfor] += 1
      end
    end

    def clear_votes
      @voted = []
      @votes = {}
      @seetarget = ""
    end

    def assign_roles
      partasstring = {}
      @participants.keys.each { |part| partasstring[part.to_s] = :normal }
      @participants = partasstring
      wolf_count = (@wolf_ratio * @participants.length).to_i
      @live_wolves = wolf_count
      while wolf_count > 0
        assign = rand(@participants.length)
        picked = @participants.keys.sort[assign]
        unless @participants[picked] == :wolf
          @participants[picked] = :wolf
          @game_wolves << picked
          wolf_count -= 1
        end
      end
      @game_wolves.sort!
      if @enable_seer
        while @seer == ""
          assign = rand(@participants.length)
          picked = @participants.keys.sort[assign]
          if @participants[picked] != :wolf
            @seer = picked
            @participants[picked] = :seer
          end
        end
      end
      @live_norms = @participants.length - @live_wolves
    end

    def apply_votes
      highest = 0
      tiebreak = []
      puts "DEBUG @votes: #{@votes.inspect}"
      @votes.each do |votee, count|
        if count > highest
          tiebreak = [votee]
          highest = count
        elsif count == highest
          tiebreak << votee
        end
      end
      puts "DEBUG tiebreak: #{tiebreak.inspect}"
      killme = nil
      if tiebreak.length > 1
        killme = tiebreak[rand(tiebreak.length)]
      elsif tiebreak.length == 1
        killme = tiebreak[0]
      end
      puts "DEBUG: killme is: #{killme.inspect}"
      return Haps.new(:action => :channel, :code => :novotes, :state => @state, :message => "No votes were made!") if killme.nil?
      was = ""
      wasn = ""
      @participants.each do |part,role|
        was = role if part == killme.to_s
        wasn = part if part == killme.to_s
      end
      @participants[wasn] = :dead
      case was
        when :wolf
          @live_wolves -= 1
          return Haps.new(:action => :channel, :code => :wolfkilled, :killed => killme, :state => @state, :message => "#{killme} has been killed at popular request")
        else 
          @live_norms -= 1
          return Haps.new(:action => :channel, :code => :normkilled, :killed => killme, :state => @state, :message => "#{killme} has been killed at popular request")
      end
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

