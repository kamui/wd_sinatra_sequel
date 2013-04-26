# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'wd_sinatra_sequel/version'

Gem::Specification.new do |gem|
  gem.name          = "wd_sinatra_sequel"
  gem.version       = WdSinatraSequel::VERSION
  gem.authors       = ["Jack Chu"]
  gem.email         = ["kamuigt@gmail.com"]
  gem.description   = %q{Basics to use Sequel with WD Sinatra.}
  gem.summary       = %q{Provides a way to get started with Sequel and WeaselDiesel on Sinatra.}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_development_dependency "pry"

  gem.add_dependency "sequel"
end
