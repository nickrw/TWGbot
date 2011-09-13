puts __FILE__
puts File.expand_path(__FILE__)
puts File.expand_path(File.dirname(__FILE__))
exit
require 'twg'

game = TWG::Game.new


game.register('player1')
game.register('player2')
game.register('player3')
game.register('player4')

game.start
exit "player1 is a wolf" if game.game_wolves.include?('player1')
puts "Wolves: " + game.game_wolves.inspect
puts "+++++++++++++++++++++++++++++++++++++++++++++"
game.game_wolves.each do |wolf|
  game.vote(wolf, 'player1', :private)
end
puts game.votes.inspect
puts game.voted.inspect
puts "+++++++++++++++++++++++++++++++++++++++++++++"
game.next_state
puts "+++++++++++++++++++++++++++++++++++++++++++++"
game.participants.keys.each do |player|
  game.vote(player,'player2', :public)
end
puts game.votes.inspect
puts game.voted.inspect
puts "+++++++++++++++++++++++++++++++++++++++++++++"
game.next_state
puts "+++++++++++++++++++++++++++++++++++++++++++++"
game.next_state
