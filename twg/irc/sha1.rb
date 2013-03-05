module TWG
  class IRC
    class SHA1
      include Cinch::Plugin
      match "sha1", :method => :sha1

      def initialize(*args)
        super
        @pwd = File.expand_path File.dirname(__FILE__)
        @isha1 = `cd #{@pwd} && git rev-parse HEAD`.strip
        @ichanges = `cd #{@pwd} && git status --porcelain`.strip
      end

      def sha1(m)

        return if !m.channel?

        sha1 = `cd #{@pwd} && git rev-parse HEAD`.strip
        changes = `cd #{@pwd} && git status --porcelain`.strip

        if sha1 != @isha1
          m.reply "!! I was started with a different commit to the current HEAD"
          m.reply "!! Running commit: #{@isha1}"
          m.reply "!! Current commit: #{sha1}"
        else
          m.reply "Running Commit: #{sha1}"
        end

        if changes != @ichanges
          m.reply describe_changes(@ichanges, 'Running working copy')
          m.reply describe_changes(changes, 'Current working copy')
        else 
          m.reply describe_changes(changes)
        end
      end

      private

      def describe_changes(changes, type='')
        type = (type.empty? ? '' : type + ': ')
        if changes.empty?
          type + "No working copy changes"
        else
          type + "Changes in the working copy:\n" + changes

        end
      end

    end
  end
end
