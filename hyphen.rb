#!/usr/bin/env ruby

require 'fileutils'
require 'shellwords'
require 'open3'
require 'optparse'
require 'bundler'
Bundler.require

class Hyphen
  VERSION = '1.0.0'
  ALLOWED_LANGUAGES = [:swift, :objc]
  ALLOWED_PLATFORMS = [:ios, :macos, :watchos, :tvos]

  def section(message)
    i = message.length + 6
    puts("-" * i)
    puts("-- " + message + " --")
    puts("-" * i)
  end

  def parse_options(args)
    options = { 
      languages: [], 
      platforms: [],
      output_path: Dir.getwd
    }

    parser = OptionParser.new do |opts|
      opts.banner = 'Hyphen - Improving Apple’s API Reference in Dash'
      opts.separator ''
      opts.separator 'Usage: hyphen [-l language] [-p platform] [-o output_path]'
      opts.separator ''
      opts.on('-l', '--language LANGUAGE', ALLOWED_LANGUAGES, "Language that should be kept. May be specified multiple times. Possible values: #{ALLOWED_LANGUAGES.join(', ')}.") do |l|
        options[:languages] << l.to_sym
      end
      opts.on('-p', '--platform PLATFORM', ALLOWED_PLATFORMS, "Platforms that should be kept. May be specified multiple times. Possible values: #{ALLOWED_PLATFORMS.join(', ')}.") do |p|
        options[:platforms] << p.to_sym
      end
      opts.on('-o', '--output OUTPUT_PATH', 'Destination path where the docset will be created. Defaults to the current directory.') do |o|
        options[:output_path] = o
      end
      opts.on('-h', '--help', 'Show this message.') do |h|
        puts opts.help
        exit
      end
      opts.on('--version', 'Print the version number and exit.') do
        puts "Hyphen version #{VERSION}"
        exit
      end
    end

    begin
      parser.parse! args
    rescue OptionParser::ParseError => e
      # Manually print the error and exit.
      # Without this begin/rescue block, a long stacktrace would flood the terminal.
      abort e.message
    end
    
    abort parser.help unless ARGV.empty?
    abort "#{parser.help}\nYou must specify at least one language to keep." if options[:languages].empty?
    abort "#{parser.help}\nYou must specify at least one platform to keep." if options[:platforms].empty?

    return options
  end

  def run(args)
    options = parse_options(args)

    docset_path = dump_docset(options)

    docset_db_path = File.join(docset_path, "Contents/Resources/docSet.dsidx")
    abort "Unable to find docset database. Expected at '#{docset_db_path}'." unless File.exists? docset_db_path
    db = SQLite3::Database.new docset_db_path

    ALLOWED_LANGUAGES.each do |lang|
      drop_language(db, lang) unless options[:languages].include? lang
    end

    filter_platforms_and_link_types(options[:platforms], docset_path, db)

    cleanup_database(db)
    
    override_styles(docset_path)

    change_identifiers(docset_path, options[:platforms])
  end

  def dump_docset(options)
    apple_api_reference_docset_path = File.expand_path "~/Library/Application Support/Dash/DocSets/Apple_API_Reference/Apple_API_Reference.docset"
    unless File.exists? apple_api_reference_docset_path
      abort "Unable to find Dash Apple_API_Reference.docset at '#{apple_api_reference_docset_path}'. Check that the 'Apple API Reference' docset is installed."
    end

    dash_apple_docs_helper_path = File.join(apple_api_reference_docset_path, "Contents/Resources/Documents/Apple Docs Helper")
    unless File.exists? dash_apple_docs_helper_path
      abort "Apple_API_Reference.docset does not contain 'Apple Docs Helper'. Please re-install the Apple API Reference from the Downloads pane in the Dash settings."
    end

    options[:output_path] = File.expand_path options[:output_path]
    abort "Output path '#{options[:output_path]}' exists and is not a directory" if File.exists?(options[:output_path]) and !File.directory?(options[:output_path])
    FileUtils.mkdir_p options[:output_path]

    section "Dumping docset"

    docset_path = File.join options[:output_path], "Apple_API_Reference.docset"
    if File.exists? docset_path
      puts "Found old docset. Deleting..."
      FileUtils.rm_rf docset_path
    end
    
    temp_docset_path = File.join options[:output_path], "Apple_API_Reference.incomplete.docset"
    if File.exists? temp_docset_path
      puts "Found old temp docset. Deleting..."
      FileUtils.rm_rf temp_docset_path
    end
    
    command = "#{dash_apple_docs_helper_path.shellescape} --dump --output #{options[:output_path].shellescape}"
    Open3.popen2e(command) do |stdin, stdout_err, wait_thr|
      while line = stdout_err.gets
        puts line
      end

      exit_status = wait_thr.value
      abort unless exit_status.success?
    end

    new_docset_path = File.join options[:output_path], "#{capitalize_platforms(options[:platforms]).join('_')}_API_Reference.docset"
    FileUtils.mv docset_path, new_docset_path

    return new_docset_path
  end

  def drop_language(db, language)
    section "Removing language #{language}"
    language = 'occ' if language == :objc
    db.execute "DELETE FROM searchIndex WHERE path LIKE '%<dash_entry_language=#{language}>%'"
  end

  def extract_filename(db_path)
    db_path[/[^#]*/]
  end

  def capitalize_platforms(platforms)
    platforms.map { |p| p.to_s.gsub 'os', 'OS' }
  end

  def filter_platforms_and_link_types(platforms, docset_path, db)
    section "Linking types"

    platforms = capitalize_platforms platforms
    grep_command = "grep -E 'Available in (#{platforms.join('|')})' -m 1"
    documents_path = File.join docset_path, "Contents/Resources/Documents/"

    ids_to_delete = []
    count = db.get_first_value("SELECT COUNT(*) from searchIndex")
    index = 0
    db.execute("SELECT id, path FROM searchIndex" ) do |row|
      puts "Progress: #{(100 * index/count.to_f).round(2)}%..." if index % 1000 == 0

      file_path = documents_path + extract_filename(row[1])
      wrong_platform = `#{grep_command} #{file_path.shellescape}`.empty?
      if wrong_platform
        ids_to_delete << row[0]
      else
        link_types(file_path, db)
      end

      index += 1
    end
    puts "Progress: 100%"

    section "Filtering platforms"
    count = ids_to_delete.size
    index = 0
    delete_statement = db.prepare("DELETE FROM searchIndex WHERE id = ?")
    ids_to_delete.each do |id|
      puts "Progress: #{(100 * index/count.to_f).round(2)}%..." if index % 1000 == 0

      delete_statement.bind_params(id)
      delete_statement.execute
      delete_statement.reset!

      index += 1
    end
    puts "Progress: 100%"
  end

  def link_types(file_path, db)
    type_regexp = /(\s|<code>|&lt;|"syntax-type">)([A-Z]{2,}(?:[A-Z][a-z]+)+)/

    return if `grep -E '#{type_regexp.source}' -m 1 #{file_path.shellescape}`.empty?
    content = IO.read file_path

    content.gsub!(type_regexp) do |match|
      type = $2
      file = file_for_type(type, db)
      next type unless file
      "#{$1}<a class=\"symbol-name\" href=\"#{file}\"><code>#{type}</code></a>"
    end
    IO.write file_path, content
  end

  def file_for_type(type, db)
    @type_cache ||= {}
    @type_lookup_statement ||= db.prepare("SELECT path FROM searchIndex WHERE name = ? ORDER BY type LIMIT 1")
  
    file = @type_cache[type]
    return file if file

    @type_lookup_statement.bind_params(type)
    @type_lookup_statement.execute do |result|
      row = result.next
      if row.nil?
        file = "" # save empty string to trigger cache hit next time
      else
        file = extract_filename row[0]
      end
    end
    @type_lookup_statement.reset!

    @type_cache[type] = file
    return file.empty? ? nil : file
  end

  def cleanup_database(db)
    section "Optimizing database"

    db.execute("VACUUM")
  end

  def override_styles(docset_path)
    section "Adjusting styles"

    overrides_path = File.expand_path 'style_overrides.css'
    css_path = File.join(docset_path, "Contents/Resources/Documents/Resources/style.css")
    `cat #{overrides_path.shellescape} >> #{css_path.shellescape}`
  end

  def change_identifiers(docset_path, platforms)
    section "Changing name"
    
    plist_path = File.join docset_path, 'Contents/Info.plist'
    
    name = "#{capitalize_platforms(platforms).join('/')} API Reference"
    
    if platforms == [:macos]
      # Bundles with the "osx" family will be displayed with a nice Finder icon in Dash
      family = "osx"
    elsif platforms.count == 1
      family = platforms.first.to_s
    else
      family = "hyphen"
    end
    
    `/usr/libexec/PlistBuddy -c "set :CFBundleName #{name}" #{plist_path.shellescape}`
    `/usr/libexec/PlistBuddy -c "set :DocSetPlatformFamily #{family}" #{plist_path.shellescape}`
  end
end

Hyphen.new.run(ARGV)
