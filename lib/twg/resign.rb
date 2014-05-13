require 'twg/plugin'

module TWG
  class Resign < TWG::Plugin
    include Cinch::Plugin

    def self.description
      "For players who find themselves called into reality (ugh)"
    end

    def initialize(*args)
      super
      commands = @lang.t_array('resign.command')
      commands.each do |command|
        self.class.match(command, :method => :resign)
      end
      __register_matchers
    end

    def resign(m)
      return if @game.nil?
      u = m.user
      role = @game.participants[u]
      return if role.nil?
      return if role == :dead

      if @game.state == :signup
        @game.deregister(u)
        @core.devoice(u)
        chansay('resign.unjoined',
          :player => u.nick,
          :count  => @game.participants.count,
          :min    => @game.min_part
        )
        return
      end

      # Let plugins which introduce non-core roles handle anything that
      # might be required from their character dying, and also handle a player
      # leaving the game that might be a target of a special character's action
      hook_async(:hook_player_resignation, 0, nil, u)

      @game.kill(u)
      @game.remove_votes_for(u)
      @game.remove_votes_by(y)
      chansay('resign.announce', :player => u)
      @core.devoice(u)

      # Ask the game if victory conditions will be met by the next state
      # change, given that we have changed the balance.
      if [:wolveswin, :humanswin].include?(@game.check_victory_condition)
        # cancel any pending state change hooks which would continue the game
        [
          :enter_night,
          :exit_night,
          :enter_day,
          :exit_day,
          :warn_vote_timeout
         ].each do |hook|
          hook_cancel(hook)
        end
        # Advanced the game state and trigger the core's victory condition
        # detection so it will announce the end of the game
        @game.next_state
        @core.check_victory_conditions
      end
    end

  end
end
