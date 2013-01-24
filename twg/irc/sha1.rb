module TWG
  class IRC
    class SHA1
      include Cinch::Plugin
      match "sha1", :method => :sha1

      def initialize(*args)
        super
      end

      def sha1(m)

        return if !m.channel?

        pwd = File.expand_path File.dirname(__FILE__)
        sha1 = `cd #{pwd} && git rev-parse HEAD`.strip
        changes = `cd #{pwd} && git status --porcelain`.strip

        m.reply "Commit: #{sha1}"
        if changes.empty?
          m.reply "No working copy changes"
        else
          m.reply "The following changes are present in my working copy"
          m.reply changes
        end
      end

    end
  end
end
