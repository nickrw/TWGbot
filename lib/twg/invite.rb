require 'twg/plugin'

module TWG
  class Invite < TWG::Plugin
    include Cinch::Plugin
    listen_to :hook_delete_invitee, :method => :delete_invitee
    match /invite ([^ ]+)$/, :method => :invite

    def initialize(*args)
      super
      # A "spam list" kept in memory to prevent someone repeatedly inviting
      # the same person over and over. Names stay in the list for an hour.
      @recent_invitees = Array.new
    end

    def invite(m, name)
      return if not m.channel?
      n = clean(name)
      return if n == m.user.nick

      # Don't allow invite spamming
      if @recent_invitees.include?(n)
        m.reply @lang.t('invite.spam', :target => n), true
        return
      end

      # Check the bot can actually do invites in this channel
      chanmodes = m.channel.users[bot]
      if not chanmodes.include?('o')
        m.reply @lang.t('invite.noops'), true
        return
      end

      rl = ratelimit(:invite, 10)
      if rl > 0
        m.reply @lang.t('invite.ratelimit', :secs => rl), true
        return
      end

      # Check the user isn't already in the channel
      user = User(n)
      return if m.channel.users.keys.include?(user)

      # Check there is a user connected by this name
      user.refresh
      if not user.online?
        m.reply @lang.t('invite.nouser', :target => n), true
        return
      end

      # Invite the user and add their name to the spam list
      m.channel.invite(n)
      @recent_invitees << n
      m.reply @lang.t('invite.confirm', :target => n), true

      # Schedule removal of the name from the spam list
      hook_async(:hook_delete_invitee, 3600, nil, n)
    end

    def delete_invitee(m, name)
      @recent_invitees.delete(name)
    end

  end
end
