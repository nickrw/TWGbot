Gem::Specification.new do |s|
  s.name = 'twg'
  s.version = '2.0.0'
  s.summary = 'The Werewolf Game.'
  s.description = 'A 6+ player IRC game bot based on Mafia.'
  s.authors = ['Nicholas Robinson-Wall']
  s.email = ['nick@robinson-wall.com']
  s.required_ruby_version = '>= 1.9.1'
  s.files = Dir['{lib}/**/*']

  # cinch 2.0.4 release version is not actually sufficient, you must build
  # the cinch gem from master https://github.com/cinchrb/cinch due to reliance
  # on 62931f96e4b82027ad9ca6cc2de91b5a6b064f35
  s.add_dependency 'cinch', '>= 2.0.4'
  s.add_dependency 'cinchize'
end
