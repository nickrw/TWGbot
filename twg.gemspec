Gem::Specification.new do |s|
  s.name = 'twg'
  s.version = '2.0.0'
  s.summary = 'The Werewolf Game.'
  s.description = 'A 6+ player IRC game bot based on Mafia.'
  s.authors = ['Nicholas Robinson-Wall']
  s.email = ['nick@robinson-wall.com']
  s.required_ruby_version = '>= 1.9.1'
  s.files = Dir['{lib,lang}/**/*']

  s.add_dependency 'cinch', '>= 2.0.5'
  s.add_dependency 'cinchize'
  s.add_dependency 'i18n', '0.6.4'
  s.add_dependency 'httparty'
end
