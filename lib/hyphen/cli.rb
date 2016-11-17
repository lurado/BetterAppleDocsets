require 'optparse'

module Hyphen
  module CLI
    def self.parse(args)
      options = { 
        languages: [:objc], 
        platforms: [:ios],
        output_path: Dir.getwd
      }

      parser = OptionParser.new do |opts|
        opts.banner = 'Hyphen - Making Apple Docs for Dash great again'
        opts.separator ''
        opts.separator 'Usage: hyphen [-l language] [-p platform] [-o output_path]'
        opts.separator ''
        opts.on('-l', '--language LANGUAGE', Hyphen::ALLOWED_LANGUAGES, "Languange that should be kept. May be specified multiple times. Possible values: #{Hyphen::ALLOWED_LANGUAGES.join(', ')}. Default value: #{options[:languages].join(', ')}.") do |l|
          options[:languages] << l.to_sym
        end
        opts.on('-p', '--platform PLATFORM', Hyphen::ALLOWED_PLATFORMS, "Platforms that should be kept. May be specified multiple times. Possible values: #{Hyphen::ALLOWED_PLATFORMS.join(', ')}. Default value: #{options[:platforms].join(', ')}.") do |p|
          options[:platforms] << p.to_sym
        end
        opts.on('-o', '--output OUTPUT_PATH', 'Destination path where the docset will be created. Defaults to the current directory.') do |o|
          options[:output_path] = o
        end
        # TODO: add option for path to Dash-Helper
        # TODO: add option for additional CSS
        opts.on('-h', '--help', 'Show this message.') do |h|
          puts opts.help
          exit
        end
        opts.on('--version', 'Print the version number and exit.') do
          puts "Hyphen version #{Hyphen::VERSION}"
          exit
        end
      end

      begin
        parser.parse! args
      rescue OptionParser::ParseError => e
        $stderr.puts e.message
        exit false
      end

      return options
    end
  end
end
