require 'fileutils'
require 'shellwords'
require 'open3'
require 'sqlite3'

module Hyphen
  class Runner
    def self.section(message)
      i = message.length + 6
      puts("-" * i)
      puts("-- " + message + " --")
      puts("-" * i)
    end

    def self.run(args)
      options = CLI.parse(args)

      docset_path = dump_docset(options)

      docset_db_path = File.join(docset_path, "Contents/Resources/docSet.dsidx")
      abort "Unable to find docset database. Expected at '#{docset_db_path}'." unless File.exists? docset_db_path
      db = SQLite3::Database.new docset_db_path

      Hyphen::ALLOWED_LANGUAGES.each do |lang|
        drop_language(db, lang) unless options[:languages].include? lang
      end

      filter_platforms_and_link_types(options[:platforms], docset_path, db)

      cleanup_database(db)
      
      override_styles(docset_path)

      change_identifiers(docset_path, options[:platforms])
    end

    def self.dump_docset(options)
      apple_api_reference_docset_path = File.expand_path "~/Library/Application Support/Dash/DocSets/Apple_API_Reference/Apple_API_Reference.docset"
      unless File.exists? apple_api_reference_docset_path
        abort "Unable to find Dash Apple_API_Reference.docset. Expected at '#{apple_api_reference_docset_path}'. Check that the 'Apple API Reference' docset is installed."
      end

      dash_apple_docs_helper_path = File.join(apple_api_reference_docset_path, "Contents/Resources/Documents/Apple Docs Helper")
      unless File.exists? dash_apple_docs_helper_path
        abort "Apple_API_Reference.docset does not contain 'Apple Docs Helper'. Maybe update to the latest docs?"
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
      
      command = "#{dash_apple_docs_helper_path.shellescape} --dump --output '#{options[:output_path].shellescape}'"
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

    def self.drop_language(db, language)
      section "Removing language #{language}"
      language = 'occ' if language == :objc
      db.execute "DELETE FROM searchIndex WHERE path LIKE '%<dash_entry_language=#{language}>%'"
    end

    def self.extract_filename(db_path)
      db_path.slice(0..(db_path.index('#') - 1))
    end

    def self.capitalize_platforms(platforms)
      platforms.map { |p| p.to_s.gsub 'os', 'OS' }
    end

    def self.filter_platforms_and_link_types(platforms, docset_path, db)
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
        wrong_platform = `#{grep_command} #{file_path}`.empty?
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

    def self.link_types(file_path, db)
      type_regexp = /(\s|<code>|&lt;|"syntax-type">)([A-Z]{2,}(?:[A-Z][a-z]+)+)/

      return if `grep -E '#{type_regexp.source}' -m 1 #{file_path}`.empty?
      content = IO.read file_path

      content.gsub!(type_regexp) do |match|
        type = $2
        file = file_for_type(type, db)
        next type unless file
        "#{$1}<a class=\"symbol-name\" href=\"#{file}\"><code>#{type}</code></a>"
      end
      IO.write file_path, content
    end

    @@type_cache = {}
    @@type_lookup_statement = nil
    def self.file_for_type(type, db)
      unless @@type_lookup_statement
        @@type_lookup_statement = db.prepare("SELECT path FROM searchIndex WHERE name = ? ORDER BY type LIMIT 1")
      end

      file = @@type_cache[type]
      return file if file

      @@type_lookup_statement.bind_params(type)
      @@type_lookup_statement.execute do |result|
        row = result.next
        if row.nil?
          file = "" # save empty string to trigger cache hit next time
        else
          file = extract_filename row[0]
        end
      end
      @@type_lookup_statement.reset!

      @@type_cache[type] = file
      return file.empty? ? nil : file
    end

    def self.cleanup_database(db)
      section "Optimizing database"

      db.execute("VACUUM")
    end

    def self.override_styles(docset_path)
      section "Adjusting styles"

      overrides_path = File.join(__dir__, '../../assets/style_overrides.css')
      css_path = File.join(docset_path, "Contents/Resources/Documents/Resources/style.css")
      `cat #{overrides_path} >> #{css_path}`
    end

    def self.change_identifiers(docset_path, platforms)
      section "Changing name"
      
      plist_path = File.join docset_path, 'Contents/Info.plist'
      name = "#{capitalize_platforms(platforms).join(' ')} API Reference"
      `/usr/libexec/PlistBuddy -c "set :CFBundleName #{name}" #{plist_path}`
      `/usr/libexec/PlistBuddy -c "set :DocSetPlatformFamily #{platforms.map(&:to_s).join}" #{plist_path}`
    end

  end
end
