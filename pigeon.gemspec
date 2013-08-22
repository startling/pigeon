Gem::Specification.new do |s|
  s.name        =  "pigeon"
  s.version     =  "0.0.0"
  s.files       =  ["lib/pigeon.rb"]
  s.executables << 'pigeon'
  s.summary     =  "opinionated unconfigurable blog engine"
  s.authors     =  ["startling"]
  s.add_dependency "haml", ">= 4.0.3"
  s.add_dependency "nokogiri", ">= 1.6.0"
  s.add_dependency "kramdown", ">= 0.6.1"
  s.add_dependency "chronic", ">= 0.9.1"
  s.add_dependency "trollop", ">= 2.0"
end
