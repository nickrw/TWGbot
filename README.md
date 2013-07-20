The Werewolf Game - an IRC bot
==============================

TWG is an IRC game for 6 or more players. It is based on the party game
[Mafia][1], substituting mob bosses with werewolves.

Thanks to the authors of the [original werewolf bot][2], which I used to play
on the UplinkCorp IRC server at a tender young age. This started off, not as a
clone, but a rewrite for learning purposes in ruby, and it has grown ever since.

   [1]: https://en.wikipedia.org/wiki/Mafia_(party_game)
   [2]: http://javatwg.sourceforge.net/

Table of contents
=================

* [How to play](#how-to-play)
  * [Night and Day](#night-and-day)
  * [Victory conditions](#victory-conditions)
  * [Roles](#roles)
* [Languages and Themes](#languages-and-themes)
* [Contributing a language pack](#contributing-a-language-pack)
  * [Getting started](#getting-started)
  * [More advanced](#more-advanced)
* [Running the bot](#running-the-bot)
  * [Configuration](#configuration)

How to play
===========

Someone in the IRC channel says "!start" to kick off registration for a new
game. Those who want to take part have 5 minutes (by default) to say "!join". 
Once the game starts the bot will randomly assign [roles](#roles) and notify all 
of the players via private message.

Once everybody has their role the first phase of the game begins: Night One.

Night and Day
-------------

The game is broken up into two phases. Simply put:

* NIGHT: The wolf chooses a victim to eat. The victim dies and is removed from
  the game at the end of the night.
* DAY: The villagers vote on who they think the wolf is. The player with the
  highest number of votes is lynched and removed from the game. Voting is
  public, and changeable.

In the event of a lynch vote tie (or a wolf eating vote at night, the case of
multiple wolves) the bot selects a victim at random from the tiebreak.

In the event of an abstain vote (!abstain, instead of !vote) being tied with a
lynch vote, the lynch wins.

E.g. If 3 players voted to lynch Player A, and three players !abstain'd, Player
A would die. It would require 4 !abstains to overrule the lynch.

If you are unclear on how the voting / abstaining / tie system works, use the
!votes command during the Day. It will print out the vote count for each player
and italicise the tied players, or the abstain line if the abstain is in effect.

Victory conditions
------------------

Victory conditions are assessed at the end of each day phase.

* Villagers win when all of the wolves have been eliminated.
* Wolves win when their count is one less than the number of humans.

Depending on the number of players this means a Day that starts with three or
four players will be the final Day, as lynching incorrectly will trigger wolf
victory conditions. Abstaining will therefore be fatal in a 3-player final day,
but not in a 4-player final day.

Roles
-----

These two are the basic roles in every game.

* *VILLAGER*

  Gets to !vote during the Day, and sleep at night.

* *WOLF*

  Gets to !vote at night on who to eat, and !vote during the day on who to
  lynch, pretending to be a villager all along. Sneaky.

  There is one wolf in the smallest game possible (6 players). The ratio of
  wolves to humans is 1 in 5, so 10 players gets a 2-wolf game, 15 a 3-wolf game
  etc.

The following special roles can also appear in games. They are implemented as 
plugins on top of the core bot, so can be turned on and off as desired. Use the 
!plugins command to find out which roles are switched on.

Percentages after the role name indicate the likelihood of the role being 
assigned in any given game. The percentage is multiplied by the number of 
non-special characters assigned so far before odds are calculated. For
per-player odds of 5% this means a 25% chance in a 6 player game, or 20% if 
another special role has already been assigned (other than a wolf).

* *SEER* (6%)

  Same as VILLAGER, but during the Night can use the !see <player> command in
  private chat to the bot. At the end of the Night the bot will reveal the
  selected player's role, unless the seer dies that night.

* *VIGILANTE* (5%)

  Same as VILLAGER, but with a single-use special ability. During the Day the
  vigilante can eliminate any player of their choosing with the !shoot <player>
  command (in the public game channel, not private message).

  This immediately triggers the following:

  * The VIGILANTE is relegated to VILLAGER.
  * The selected player is removed from the game.
  * The role of the selected player is revealed to the channel.
  * The Day is ended, without a lunch. Votes for that day's lynch are discarded.

  Normally the vigilante never survives the following Night as the villagers 
  know that the vigilante can't be the wolf.

Languages and Themes
====================

TWG has i18n support. All of the game messages can be translated / re-themed, 
and all of the player commands can also be changed.

The bot can be switched between language packs while running, between games. Use 
the **!langs** command to see the list of supported language packs.

Contributing a language pack
============================

If you are interested in translating the game into another language, or putting 
a non-werewolf spin on things, it is helpful to have an understanding of basic 
YAML syntax. Have a quick look at lang/default.yml

Getting started
---------------

1. Use lang/default.yml as a starting point. Copy it to lang/somethingelse.yml
2. Edit line one of your new file. Make 'default' match your file name.
3. Edit the description. If your language doesn't have a description it will not
   show up in the list printed by the !langs command.
4. Change the start.start entry ("TWG has been started by ... ") to better
   identify your language pack. Please change 'TWG' to something else, as this
   should only be used by the default language.
5. Please avoid changing the start.registration key if you are writing a new
   theme in English. This is often used as part of players' custom IRC highlight
   setup so interested parties can subscribe to notifications of new games
   starting.
6. Start changing the rest of the entries to match your language/theme.
7. If you aren't changing a partiular key, delete it! The bot will fall back to
   the default language for any key not present in your pack.

More advanced
-------------

* YAML arrays can be given for *any* key (with the exception of those defining 
  commands). The bot will pick one item at random from the array each time it 
  speaks the key. This can be used to make the bot seem a little less
  monotonous, as it won't necessarily say the same things constantly.

  For example:

        cheese: "I like cheese"

  The bot will always say "I like cheese" for that key

        cheese:
          - "I like cheddar"
          - "I like wensleydale"

  The bot will pick randomly between these two different cheeses each time.

* Interpolation variable ("So and so %{player} did X") can be used multiple 
  times within a string, and they may also be omitted.

  If you try to use an unexpected (hint: if it isn't used by the same key in
  default.yml, it is unexpected) interpolation variable the bot may print a 
  translation error instead of the string. It will print the string verbatim if 
  there are no interpolation variables expected at all, but it will print a 
  translation error if you make up a variable name on a translation that passes 
  through another variable.

* The single word 'command' keys are the various commands the bot responds to.
  In general please try to avoid changing these, as context switching between
  language packs can be confusing and disorientating enough without having to
  remember that !vote is something else. If you do want to change some of them
  make sure you also update the various references the bot makes to its commands
  elsewhere.

Running the bot
===============

The set up:

    git clone https://github.com/nickrw/TWGbot.git
    cd TWGbot
    gem build twg.gemspec
    gem install --no-ri --no-rdoc twg*.gem
    cp example.yml cinchize.yml
    mkdir cinchize

At this point you want to edit cinchize.yml to get the bot to connect to your
preferred IRC network. See the [Configuration](#configuration) section below for
more information about the TWG-specific plugin options.

Once the configuration is to your liking, run:

    cinchize --start freenode

Where *freenode* is the network you specified in cinchize.yml (it is the key on
line 6 in example.yml).

Configuration
-------------

TODO
