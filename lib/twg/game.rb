module TWG
  class Game

    attr_reader :participants
    attr_reader :state
    attr_reader :live_wolves
    attr_reader :live_norms
    attr_reader :votes
    attr_reader :game_wolves
    attr_reader :min_part
    attr_reader :iteration

    def initialize
      reset
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
      @votes = {}
      @votelock = false
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

    def deregister(nick)
      return false if @state != :signup
      return false if not @participants.keys.include?(nick)
      @participants.delete(nick)
      return true
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

      # Replace votes for and by the player
      tvotes = @votes.dup
      tvotes.each do |votee,voters|
        if votee == oldnick
          @votes[newnick] = voters
          @votes.delete(oldnick)
        end
        if voters.include?(oldnick)
          @votes[votee].delete(oldnick)
          @votes[votee] << newnick
        end
      end
      tvotes = nil

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

    def lock
      @votelock = true
      return true
    end

    def unlock
      @votelock = false
      return true
    end

    # Receives and process a vote from the outside world
    def vote(nick,vfor,type)
      return {:code => :notvotablestate} if not [:day, :night].include?(@state)
      return {:code => :votelocked} if @votelock && (nick.class != Symbol)
      if ((@state == :night) && (type == :channel) || ((@state == :day) && (type == :private)))
        return {:code => :illegalvotetype}
      end
      return {:code => :voternotplayer} if not player?(nick)
      return {:code => :dead} if dead?(nick)
      return {:code => :self} if nick == vfor
      return {:code => :voteenotplayer} if not player?(vfor)
      return {:code => :voteedead} if dead?(vfor)
      if @state == :night
        return {:code => :notawolf} if not @game_wolves.include?(nick) || (nick.class == Symbol)
        return {:code => :fellowwolf} if @game_wolves.include?(vfor)
      end
      previous = record_vote(nick,vfor)
      return {:code => :confirmvote, :previous => previous}
    end

    def abstain(nick)
      role = @participants[nick]
      return role if role.nil? || role == :dead
      return :notvotablestate if not [:day, :night].include?(@state)
      return :invalid if @state == :night && role != :wolf
      record_vote(nick, :abstain)
      true
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
      unlock
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

    # Returns nil for successful new vote.
    # Returns name of previous vote for successful changed vote.
    def record_vote(nick,vfor)
      old = nil
      tvotes = @votes.dup
      tvotes.each do |votee, voters|
        next if voters.nil?
        if voters.include?(nick)
          @votes[votee].delete(nick)
          if @votes[votee].empty?
            @votes.delete(votee)
          end
          old = votee
          break
        end
      end
      @votes[vfor] ||= Array.new
      @votes[vfor] << nick
      return old
    end

    def remove_votes_for(nick)
      @votes.delete(nick)
    end

    def remove_votes_by(nick)
      @votes.dup.each do |votee,voters|
        if voters.include?(nick)
          @votes[votee].delete(nick)
        end
      end
    end

    def clear_votes
      @votes = {}
    end

    def assign_roles

      @live_wolves = (@wolf_ratio * @participants.length).to_i
      @live_norms = @participants.length - @live_wolves
      @game_wolves = @participants.keys.shuffle[0..(@live_wolves-1)].sort

      @game_wolves.each do |wolf|
        @participants[wolf] = :wolf
      end

    end

    def apply_votes(perform_kill=true)
      highest = 0
      tiebreak = []
      @votes.each do |votee, voters|
        next if voters.nil?
        if voters.count > highest
          tiebreak = [votee]
          highest = voters.count
        elsif voters.count == highest
          tiebreak << votee
        end
      end
      if tiebreak.length > 1
        tiebreak.delete(:abstain)
      end
      return tiebreak if not perform_kill
      killed = tiebreak.shuffle[0]
      return nil if killed.nil?
      return :abstain if killed == :abstain
      role = kill(killed)
      return [killed, role]
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
      return true if name.class == Symbol #Symbols are used by plugins as actors
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

