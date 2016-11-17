$LOAD_PATH.unshift 'lib'
require 'hyphen/version'

Gem::Specification.new do |s|
  s.name         = "hyphen"
  s.version      = Hyphen::VERSION
  s.date         = Time.now.strftime('%Y-%m-%d')
  s.summary      = "Making Apple Docs for Dash great again"
  s.homepage     = "https://github.com/lurado/hyphen"
  s.email        = "info@lurado.com"
  s.authors      = [ "Julian Raschke und Sebastian Ludwig GbR" ]
  s.has_rdoc     = false
  s.license      = "MIT"

  s.files        = %w( Gemfile README.md LICENSE )
  s.files       += Dir.glob("lib/**/*")
  s.files       += Dir.glob("bin/**/*")
  s.files       += Dir.glob("assets/**/*")

  s.required_ruby_version = ">= 2.0"
  s.add_runtime_dependency('sqlite3', "~> 1.3.0")

  s.executables  = %w( hypen )
  s.description  = <<desc
  Apple did a terrible job with the API docs bundeled with Xcode 8. This gem prepares a 
  docset to be used with Dash.app. It removes unwanted platforms and languages and links
  many types.
desc
end
