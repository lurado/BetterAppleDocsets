module Hyphen
  class Error < StandardError
  end

  ALLOWED_LANGUAGES = [:swift, :objc]
  ALLOWED_PLATFORMS = [:ios, :macos, :watchos, :tvos]

  require 'hyphen/cli'
  require 'hyphen/runner'
  require 'hyphen/version'
end
