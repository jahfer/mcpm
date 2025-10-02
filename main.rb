#!/usr/bin/env ruby

# frozen_string_literal: true

# A script to manage and update Modrinth mods for a Fabric Minecraft server.
# It uses a YAML configuration file (mods.yml) to define which mods to manage,
# then checks for updates, handles downloads, and allows for easy reverting of changes.
#
# The script matches installed JAR files using filename patterns defined in the
# YAML configuration, making it more reliable than trying to extract metadata
# from mod files themselves.
#
# Author: Your Friendly AI Assistant
# Version: 5.0.0 - YAML Configuration Based

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'cli-kit'
  gem 'cli-ui'
  gem 'net-http'
  gem 'json'
  gem 'fileutils'
  gem 'rubyzip'
  gem 'yaml'
end

require 'net/http'
require 'json'
require 'fileutils'
require 'zip'
require 'uri'
require 'yaml'

# Initialize CLI Kit
CLI::UI::StdoutRouter.enable

# --- CONFIGURATION ---
config_base_dir = File.join('opt', 'mscs', 'worlds', 'friends')

CONFIG = {
  server_name: 'redstoner',
  base_dir: config_base_dir,
  mods_dir: File.join(config_base_dir, 'mods'),
  backup_dir: File.join(config_base_dir, 'mod_backups'),
  mods_config_file: File.join(config_base_dir, 'mods.yml'),
  user_agent: "Mod-Updater (for user: #{ENV['USER']})",
  modrinth_token: ENV['MODRINTH_TOKEN'] # Personal access token from environment variable
}.freeze
# --- END CONFIGURATION ---

# Safety constants
SUPPORTED_EXTENSIONS = %w[.jar].freeze
MAX_BACKUP_DIRS = 10

# A simple structure to hold all the info about a mod we're managing.
ManagedMod = Struct.new(:project_id, :name, :type, :installed_info, :filename_pattern, :depends_on, :is_platform)

# --- HELPER METHODS ---

def add_modrinth_auth_headers(request)
  # Add User-Agent header (required by Modrinth API)
  request['User-Agent'] = CONFIG[:user_agent]
  
  # Add authorization header if token is available
  if CONFIG[:modrinth_token] && !CONFIG[:modrinth_token].empty?
    request['Authorization'] = CONFIG[:modrinth_token]
  end
  
  request
end

def validate_modrinth_token
  return true unless CONFIG[:modrinth_token] && !CONFIG[:modrinth_token].empty?
  
  begin
    uri = URI('https://api.modrinth.com/v2/user')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Get.new(uri)
    add_modrinth_auth_headers(request)
    
    response = http.request(request)
    
    case response.code
    when '200'
      user_data = JSON.parse(response.body)
      puts CLI::UI.fmt("{{green:✓}} Modrinth API token validated for user: #{user_data['username']}")
      return true
    when '401'
      puts CLI::UI.fmt("{{red:✗}} Invalid Modrinth API token")
      return false
    else
      puts CLI::UI.fmt("{{yellow:⚠}} Unable to validate Modrinth API token (HTTP #{response.code})")
      return true # Don't block execution for other errors
    end
  rescue => e
    puts CLI::UI.fmt("{{yellow:⚠}} Error validating Modrinth API token: #{e.message}")
    return true # Don't block execution for network errors
  end
end

def validate_config
  CLI::UI::Frame.open("Configuration Validation") do
    puts CLI::UI.fmt("{{blue:🔍}} Validating configuration...")

    errors = []

    # Validate server name is safe
    unless CONFIG[:server_name].match?(/\A[a-zA-Z0-9_-]+\z/)
      errors << "Server name contains unsafe characters: #{CONFIG[:server_name]}"
    end

    # Validate base_dir does not contain unsafe characters
    if CONFIG[:base_dir].include?('..')
      errors << "Base directory path contains potentially unsafe '..' components: #{CONFIG[:base_dir]}"
    end

    # Create base, mods, and backup directories if they don't exist
    [CONFIG[:base_dir], CONFIG[:mods_dir], CONFIG[:backup_dir]].each do |dir|
      next if Dir.exist?(dir)
      begin
        FileUtils.mkdir_p(dir)
        puts CLI::UI.fmt("  {{green:✓}} Created directory: #{dir}")
      rescue SystemCallError => e
        errors << "Cannot create directory #{dir}: #{e.message}"
      end
    end

    # Validate directories are writable
    [CONFIG[:mods_dir], CONFIG[:backup_dir]].each do |dir|
      if Dir.exist?(dir) && !File.writable?(dir)
        errors << "Directory is not writable: #{dir}"
      end
    end

    # Validate mods config file exists
    unless File.exist?(CONFIG[:mods_config_file])
      errors << "Mods configuration file does not exist: #{CONFIG[:mods_config_file]}"
      errors << "Please create it at the specified location."
    end

    # Validate Modrinth API token if provided
    unless validate_modrinth_token
      errors << "Invalid Modrinth API token"
    end

    if errors.any?
      puts CLI::UI.fmt("{{red:✗}} Configuration validation failed:")
      errors.each { |error| puts CLI::UI.fmt("  {{red:•}} #{error}") }
      exit 1
    else
      puts CLI::UI.fmt("{{green:✓}} Configuration is valid")
      
      # Show authentication status
      if CONFIG[:modrinth_token] && !CONFIG[:modrinth_token].empty?
        puts CLI::UI.fmt("{{blue:🔐}} Using authenticated Modrinth API access")
      else
        puts CLI::UI.fmt("{{yellow:⚠}} Using unauthenticated Modrinth API access (rate limited)")
        puts CLI::UI.fmt("{{gray:💡}} Set MODRINTH_TOKEN environment variable for higher rate limits")
      end
    end
  end
end

def load_mods_config
  begin
    config_data = YAML.load_file(CONFIG[:mods_config_file])
    unless config_data && config_data['mods']
      puts CLI::UI.fmt("{{red:✗}} Invalid mods configuration: missing 'mods' section")
      exit 1
    end
    
    mods = config_data['mods'].map do |mod_config|
      required_fields = %w[project_id name type filename_pattern]
      missing_fields = required_fields.reject { |field| mod_config[field] }
      
      if missing_fields.any?
        puts CLI::UI.fmt("{{red:✗}} Mod configuration missing required fields: #{missing_fields.join(', ')}")
        exit 1
      end
      
      unless %w[server_only client_and_server].include?(mod_config['type'])
        puts CLI::UI.fmt("{{red:✗}} Invalid mod type '#{mod_config['type']}' for #{mod_config['name']}. Must be 'server_only' or 'client_and_server'")
        exit 1
      end
      
      {
        project_id: mod_config['project_id'],
        name: mod_config['name'],
        type: mod_config['type'].to_sym,
        filename_pattern: mod_config['filename_pattern'],
        depends_on: mod_config['depends_on'] || [],
        is_platform: mod_config['is_platform'] || false
      }
    end
    
    if mods.empty?
      puts CLI::UI.fmt("{{red:✗}} No mods defined in configuration file")
      exit 1
    end
    
    mods
  rescue Errno::ENOENT
    puts CLI::UI.fmt("{{red:✗}} Mods configuration file not found: #{CONFIG[:mods_config_file]}")
    exit 1
  rescue Psych::SyntaxError => e
    puts CLI::UI.fmt("{{red:✗}} Invalid YAML syntax in mods configuration: #{e.message}")
    exit 1
  rescue => e
    puts CLI::UI.fmt("{{red:✗}} Error loading mods configuration: #{e.message}")
    exit 1
  end
end

def safe_path?(path)
  # Ensure path is within our configured base directory and doesn't contain traversal
  base_dir_resolved = File.expand_path(CONFIG[:base_dir])
  resolved_path = File.expand_path(path)
  
  resolved_path.start_with?(base_dir_resolved) && !path.include?('..')
end

def validate_file_operation(operation, source_path, destination_path = nil)
  errors = []
  
  # Validate source path
  unless File.exist?(source_path)
    errors << "Source file does not exist: #{source_path}"
  end
  
  unless safe_path?(source_path)
    errors << "Source path is outside safe directories: #{source_path}"
  end
  
  # Validate destination path if provided
  if destination_path
    unless safe_path?(destination_path) || safe_path?(File.dirname(destination_path))
      errors << "Destination path is outside safe directories: #{destination_path}"
    end
    
    if operation == :move && File.exist?(destination_path)
      errors << "Destination file already exists: #{destination_path}"
    end
  end
  
  # Validate file extension for jar files
  if File.extname(source_path).downcase == '.jar'
    unless SUPPORTED_EXTENSIONS.include?(File.extname(source_path).downcase)
      errors << "Unsupported file type: #{source_path}"
    end
  end
  
  errors
end

def run_server_command(action)
  CLI::UI::Frame.open("Server Management") do
    # Validate action is safe (whitelist approach)
    allowed_actions = %w[start stop restart status]
    unless allowed_actions.include?(action)
      puts CLI::UI.fmt("{{red:✗}} Invalid server action: #{action}")
      return false
    end
    
    # Validate server name is safe (already validated in validate_config, but double-check)
    unless CONFIG[:server_name].match?(/\A[a-zA-Z0-9_-]+\z/)
      puts CLI::UI.fmt("{{red:✗}} Invalid server name: #{CONFIG[:server_name]}")
      return false
    end
    
    puts CLI::UI.fmt("{{yellow:Running 'mscs #{action} #{CONFIG[:server_name]}'...}}")
    
    # Use array form of system to prevent command injection
    success = system('mscs', action, CONFIG[:server_name])
    if success
      puts CLI::UI.fmt("{{green:✓}} Command finished successfully.")
      return true
    else
      puts CLI::UI.fmt("{{red:✗}} Command failed with exit code #{$?.exitstatus}.")
      return false
    end
  end
end

def get_version_from_jar(jar_path)
  # Simplified version extraction that only gets version and MC version for display
  begin
    Zip::File.open(jar_path) do |zip_file|
      entry = zip_file.find_entry('fabric.mod.json')
      return { version: nil, mc_version: nil } unless entry

      raw_content = entry.get_input_stream.read
      cleaned_content = raw_content.gsub(/[\x00-\x1F\x7F]/, '')
      json_data = JSON.parse(cleaned_content)
      
      {
        version: json_data['version'],
        mc_version: json_data.dig('depends', 'minecraft')
      }
    end
  rescue => e
    # Return unknowns on any error - this is just for display purposes
    { version: nil, mc_version: nil }
  end
end

def get_minecraft_version(managed_mods = nil)
  # Read Minecraft version from mscs.properties file
  mscs_properties_path = File.join(CONFIG[:base_dir], 'mscs.properties')
  
  begin
    if File.exist?(mscs_properties_path)
      File.foreach(mscs_properties_path) do |line|
        line.strip!
        next if line.empty? || line.start_with?('#')
        
        if line.start_with?('mscs-server-version=')
          version = line.split('=', 2)[1]
          return version if version && !version.empty?
        end
      end
    end
  rescue => e
    puts CLI::UI.fmt("{{yellow:⚠}} Error reading mscs.properties: #{e.message}")
  end
  
  # Fallback: try to detect from mods if managed_mods is provided
  if managed_mods
    # Find the Fabric API mod from our managed mods list
    fabric_api_mod = managed_mods.find { |mod| mod.project_id == 'P7dR8mSH' }
    
    if fabric_api_mod && fabric_api_mod.installed_info[:mc_version] != 'unknown'
      mc_version_match = fabric_api_mod.installed_info[:mc_version].match(/(\d+\.\d+(\.\d+)?)/)
      if mc_version_match
        return mc_version_match[1]
      end
    end
    
    # Fallback: try to detect from any mod with a valid MC version
    managed_mods.each do |mod|
      if mod.installed_info[:mc_version] != 'unknown'
        mc_version_match = mod.installed_info[:mc_version].match(/(\d+\.\d+(\.\d+)?)/)
        return mc_version_match[1] if mc_version_match
      end
    end
  end
  
  puts CLI::UI.fmt("{{red:✗}} Could not determine Minecraft version from mscs.properties or managed mods.")
  puts CLI::UI.fmt("{{yellow:💡}} Ensure mscs.properties exists with mscs-client-version or mscs-server-version set.")
  exit 1
end

# Fetches the latest version information for a mod from Modrinth

def find_latest_version(project_id, game_version)
  # Unchanged: Finds the latest compatible version file.
  uri = URI("https://api.modrinth.com/v2/project/#{project_id}/version")
  params = { loaders: "[\"fabric\"]", game_versions: "[\"#{game_version}\"]" }
  uri.query = URI.encode_www_form(params)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Get.new(uri)
  add_modrinth_auth_headers(request)

  response = http.request(request)
  return nil unless response.is_a?(Net::HTTPSuccess)

  versions = JSON.parse(response.body)
  return nil if versions.empty?

  latest = versions.first
  primary_file = latest['files'].find { |f| f['primary'] }
  {
    version_number: latest['version_number'],
    url: primary_file['url'],
    filename: primary_file['filename']
  }
end

def download_file(url, destination_path)
  # Validate destination path is safe
  unless safe_path?(destination_path) || safe_path?(File.dirname(destination_path))
    raise "Unsafe destination path: #{destination_path}"
  end
  
  # Create temporary file first, then move to final location
  temp_path = "#{destination_path}.tmp"
  
  begin
    uri = URI(url)
    puts CLI::UI.fmt("    {{gray:•}} Downloading from: #{uri.host}")
    
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      request = Net::HTTP::Get.new(uri)
      add_modrinth_auth_headers(request)
      
      http.request(request) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          raise "HTTP error: #{response.code} #{response.message}"
        end
        
        File.open(temp_path, 'wb') do |file|
          response.read_body do |chunk|
            file.write(chunk)
          end
        end
      end
    end
    
    # Verify the downloaded file is a valid jar (basic check)
    unless File.size(temp_path) > 0
      raise "Downloaded file is empty"
    end
    
    # Move temp file to final location
    FileUtils.mv(temp_path, destination_path)
    puts CLI::UI.fmt("    {{green:✓}} Download completed: #{File.basename(destination_path)}")
    
  rescue => e
    # Clean up temp file if it exists
    File.delete(temp_path) if File.exist?(temp_path)
    raise "Download failed: #{e.message}"
  end
end

# --- CORE LOGIC ---

def cleanup_old_backups
  # Keep only the most recent backups to prevent disk space issues
  backup_dirs = Dir.glob(File.join(CONFIG[:backup_dir], 'backup_*')).sort
  
  if backup_dirs.length > MAX_BACKUP_DIRS
    old_backups = backup_dirs[0..-(MAX_BACKUP_DIRS + 1)]
    puts CLI::UI.fmt("{{yellow:🧹}} Cleaning up #{old_backups.length} old backup(s)...")
    
    old_backups.each do |old_backup|
      begin
        FileUtils.rm_rf(old_backup)
        puts CLI::UI.fmt("  {{gray:•}} Removed: #{File.basename(old_backup)}")
      rescue => e
        puts CLI::UI.fmt("  {{yellow:⚠}} Could not remove #{File.basename(old_backup)}: #{e.message}")
      end
    end
  end
end

def perform_dry_run(selected_updates, timestamp)
  CLI::UI::Frame.open("Dry Run") do
    puts CLI::UI.fmt("{{blue:🎯}} Performing dry run - no actual changes will be made")
    puts CLI::UI.fmt("{{gray:This shows you exactly what would happen during the update.}}")
    
    session_backup_dir = File.join(CONFIG[:backup_dir], "backup_#{timestamp}")
    
    puts CLI::UI.fmt("\n{{yellow:📋}} Planned operations:")
    puts CLI::UI.fmt("  {{blue:1.}} Stop Minecraft server")
    puts CLI::UI.fmt("  {{blue:2.}} Create backup directory: {{underline:#{session_backup_dir}}}")
    
    selected_updates.each_with_index do |update, i|
      old_path = update[:managed_mod].installed_info[:path]
      new_filename = update[:new_mod][:filename]
      
      puts CLI::UI.fmt("  {{blue:#{i + 3}.}} Update {{cyan:#{update[:managed_mod].name}}}:")
      puts CLI::UI.fmt("      {{gray:•}} Move {{gray:#{File.basename(old_path)}}} to backup")
      puts CLI::UI.fmt("      {{gray:•}} Download {{green:#{new_filename}}} to mods folder")
    end
    
    puts CLI::UI.fmt("  {{blue:#{selected_updates.length + 3}.}} Start Minecraft server")
    
    puts CLI::UI.fmt("\n{{yellow:📁}} Files that would be affected:")
    selected_updates.each do |update|
      old_path = update[:managed_mod].installed_info[:path]
      
      # Validate each operation
      validation_errors = validate_file_operation(:move, old_path, session_backup_dir)
      if validation_errors.any?
        puts CLI::UI.fmt("  {{red:✗}} {{cyan:#{File.basename(old_path)}}} - VALIDATION ERRORS:")
        validation_errors.each { |error| puts CLI::UI.fmt("      {{red:•}} #{error}") }
      else
        puts CLI::UI.fmt("  {{green:✓}} {{cyan:#{File.basename(old_path)}}} - Ready for backup and update")
      end
    end
    
    proceed = CLI::UI::Prompt.confirm("\nDoes this look correct? Proceed with actual update?")
    return proceed
  end
end

def get_all_managed_mods
  CLI::UI::Frame.open("Mod Discovery") do
    puts CLI::UI.fmt("{{blue:🔍}} Loading mod configuration and discovering installed mods...")
    
    # Load the mod configuration from YAML
    mod_configs = load_mods_config
    puts CLI::UI.fmt("{{green:✓}} Loaded configuration for {{bold:#{mod_configs.length}}} mod(s)")
    
    # Find installed JAR files
    jar_files = Dir.glob("#{CONFIG[:mods_dir]}/*.jar")
    puts CLI::UI.fmt("{{blue:📁}} Found {{bold:#{jar_files.length}}} JAR file(s) in mods directory")
    
    managed_mods = []
    unmatched_configs = []
    unmatched_jars = jar_files.dup
    
    # Collect mod information and display messages
    processing_messages = []
    
    CLI::UI::Progress.progress do |bar|
      mod_configs.each_with_index do |mod_config, i|
        bar.tick(set_percent: (i + 1).to_f / mod_configs.length)
        
        # Find JAR files that match this mod's filename pattern
        pattern = Regexp.new(mod_config[:filename_pattern], Regexp::IGNORECASE)
        matching_jars = jar_files.select { |jar| File.basename(jar).match?(pattern) }
        
        if matching_jars.empty?
          processing_messages << { type: :warning, message: "No installed file found for {{cyan:#{mod_config[:name]}}} (pattern: #{mod_config[:filename_pattern]})" }
          unmatched_configs << mod_config
        elsif matching_jars.length > 1
          processing_messages << { type: :warning, message: "Multiple files match {{cyan:#{mod_config[:name]}}} pattern:" }
          matching_jars.each { |jar| processing_messages << { type: :info, message: "  {{gray:•}} #{File.basename(jar)}" } }
          processing_messages << { type: :info, message: "Using first match: #{File.basename(matching_jars.first)}" }
          
          # Use the first match and remove it from unmatched
          jar_path = matching_jars.first
          unmatched_jars.delete(jar_path)
          
          # Try to extract version from the JAR for display purposes
          version_info = get_version_from_jar(jar_path)
          installed_info = {
            path: jar_path,
            filename: File.basename(jar_path),
            version: version_info[:version] || 'unknown',
            mc_version: version_info[:mc_version] || 'unknown'
          }
          
          managed_mods << ManagedMod.new(
            mod_config[:project_id],
            mod_config[:name],
            mod_config[:type],
            installed_info,
            mod_config[:filename_pattern],
            mod_config[:depends_on],
            mod_config[:is_platform]
          )
          processing_messages << { type: :success, message: "{{cyan:#{mod_config[:name]}}} [{{cyan:#{mod_config[:type].to_s.gsub('_', '-')}}}] - v#{installed_info[:version]}" }
        else
          # Exactly one match found
          jar_path = matching_jars.first
          unmatched_jars.delete(jar_path)
          
          # Try to extract version from the JAR for display purposes
          version_info = get_version_from_jar(jar_path)
          installed_info = {
            path: jar_path,
            filename: File.basename(jar_path),
            version: version_info[:version] || 'unknown',
            mc_version: version_info[:mc_version] || 'unknown'
          }
          
          managed_mods << ManagedMod.new(
            mod_config[:project_id],
            mod_config[:name],
            mod_config[:type],
            installed_info,
            mod_config[:filename_pattern],
            mod_config[:depends_on],
            mod_config[:is_platform]
          )
          processing_messages << { type: :success, message: "{{cyan:#{mod_config[:name]}}} [{{cyan:#{mod_config[:type].to_s.gsub('_', '-')}}}] - v#{installed_info[:version]}" }
        end
      end
    end
    
    # Display all processing messages after progress bar is complete
    processing_messages.each do |msg|
      case msg[:type]
      when :success
        puts CLI::UI.fmt("  {{green:✓}} #{msg[:message]}")
      when :warning
        puts CLI::UI.fmt("  {{yellow:⚠}} #{msg[:message]}")
      when :info
        puts CLI::UI.fmt("    #{msg[:message]}")
      end
    end

    # Report on unmatched configurations
    if unmatched_configs.any?
      puts CLI::UI.fmt("\n{{yellow:📋}} Mods configured but not found:")
      unmatched_configs.each do |config|
        puts CLI::UI.fmt("  {{yellow:•}} {{cyan:#{config[:name]}}} (looking for: #{config[:filename_pattern]})")
      end
      puts CLI::UI.fmt("{{gray:💡}} These mods may need to be downloaded or their filename patterns updated.")
    end

    # Report on unmatched JAR files
    if unmatched_jars.any?
      puts CLI::UI.fmt("\n{{yellow:📋}} Unmanaged JAR files found in mods directory:")
      unmatched_jars.each do |jar|
        puts CLI::UI.fmt("  {{yellow:•}} #{File.basename(jar)}")
      end
      puts CLI::UI.fmt("{{gray:💡}} These files do not match any configured mod patterns.")
    end
    
    managed_mods
  end
end

def is_release_version(version)
  # Check if a Minecraft version is a stable release version (not snapshot/pre-release)
  # Release versions follow the pattern: X.Y or X.Y.Z (e.g., "1.21", "1.21.1")
  # Snapshot versions include:
  #   - Weekly snapshots: "24w03b", "23w45a"
  #   - Pre-releases: "1.21-pre1", "1.21-rc1"
  #   - Release candidates: "1.21.1-rc1"
  #   - Experimental snapshots: "1.21_experimental-snapshot-1"
  
  return false if version.nil? || version.empty?
  
  # Pattern for stable release versions: major.minor or major.minor.patch
  release_pattern = /\A\d+\.\d+(\.\d+)?\z/
  
  # If it matches the release pattern and doesn't contain experimental keywords
  version.match?(release_pattern) &&
    !version.include?('experimental') &&
    !version.include?('snapshot') &&
    !version.include?('pre') &&
    !version.include?('rc')
end

def get_all_minecraft_versions_for_mod(project_id)
  # Fetches all available Minecraft versions for a given mod, filtering out snapshots/pre-releases.
  uri = URI("https://api.modrinth.com/v2/project/#{project_id}/version")
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Get.new(uri)
  add_modrinth_auth_headers(request)
  
  response = http.request(request)
  return [] unless response.is_a?(Net::HTTPSuccess)
  
  versions = JSON.parse(response.body)
  all_versions = versions.flat_map { |v| v['game_versions'] }.uniq
  
  # Filter to only include stable release versions
  all_versions.select { |version| is_release_version(version) }
end

def find_furthest_supported_minecraft_version(managed_mods)
  # Experimental: Tries to find the latest common Minecraft version across all mods.
  puts CLI::UI.fmt("{{blue:🔬}} Experimental: Finding furthest supported Minecraft version...")
  all_versions_per_mod = []
  
  CLI::UI::Progress.progress do |bar|
    managed_mods.each_with_index do |mod, i|
      bar.tick(set_percent: (i + 1).to_f / managed_mods.length)
      all_versions_per_mod << get_all_minecraft_versions_for_mod(mod.project_id)
    end
  end
  
  # Find the intersection of all version lists
  common_versions = all_versions_per_mod.reduce(:&)
  
  if common_versions.nil? || common_versions.empty?
    puts CLI::UI.fmt("{{red:✗}} No common Minecraft version found across all managed mods.")
    return nil
  end
  
  # Sort versions to find the latest (this is a simplistic sort)
  latest_common_version = common_versions.sort_by { |v| v.split('.').map(&:to_i) }.last
  
  puts CLI::UI.fmt("{{green:✓}} Latest common Minecraft version: #{latest_common_version}")
  latest_common_version
end

def handle_list_mods
  # Lists all managed mods and their current status.
  managed_mods = get_all_managed_mods
  
  CLI::UI::Frame.open("Mod Listing") do
    puts CLI::UI.fmt("{{bold:Managed Mods (#{managed_mods.length} total)}}")
    
    if managed_mods.empty?
      puts CLI::UI.fmt("{{info:No managed mods found.}}")
      return
    end
    
    managed_mods.each_with_index do |mod, i|
      puts CLI::UI.fmt("\n{{bold:#{i + 1}. #{mod.name}}}")
      puts CLI::UI.fmt("   {{gray:Project ID:}} #{mod.project_id}")
      puts CLI::UI.fmt("   {{gray:Type:}} #{mod.type.to_s.gsub('_', '-')}")
      puts CLI::UI.fmt("   {{gray:Installed:}} #{mod.installed_info[:filename]} (v#{mod.installed_info[:version]})")
      puts CLI::UI.fmt("   {{gray:MC Version:}} #{mod.installed_info[:mc_version]}")
    end
  end
end

def handle_check_updates
  # Checks for updates for all managed mods.
  managed_mods = get_all_managed_mods
  
  CLI::UI::Frame.open("Update Check") do
    puts CLI::UI.fmt("{{blue:🔍}} Checking for updates...")
    mc_version = get_minecraft_version(managed_mods)
    puts CLI::UI.fmt("{{info:Using Minecraft version: #{mc_version}}}")
    
    updates_available = []
    CLI::UI::Progress.progress do |bar|
      managed_mods.each_with_index do |mod, i|
        bar.tick(set_percent: (i + 1).to_f / managed_mods.length)
        latest_version = find_latest_version(mod.project_id, mc_version)
        if latest_version && latest_version[:version_number] != mod.installed_info[:version]
          updates_available << { managed_mod: mod, new_mod: latest_version }
        end
      end
    end
    
    if updates_available.empty?
      puts CLI::UI.fmt("\n{{green:✓}} All mods are up to date for Minecraft #{mc_version}.")
      return
    end
    
    puts CLI::UI.fmt("\n{{yellow:🔄}} Updates available for Minecraft #{mc_version}:")
    updates_available.each_with_index do |update, i|
      type_label = update[:managed_mod].type == :server_only ? 'Server-Only' : 'CLIENT UPDATE REQUIRED'
      type_color = update[:managed_mod].type == :server_only ? 'green' : 'red'
      old_version = update[:managed_mod].installed_info[:version]
      puts CLI::UI.fmt("  {{bold:#{i + 1}.}} {{cyan:#{update[:managed_mod].name}}} ({{#{type_color}:#{type_label}}})")
      puts CLI::UI.fmt("      {{yellow:#{old_version}}} → {{green:#{update[:new_mod][:version_number]}}}")
    end
    
    # Check for future updates on a newer MC version
    puts CLI::UI.fmt("\n{{blue:🔬}} Checking for updates on future Minecraft versions...")
    future_mc_version = find_furthest_supported_minecraft_version(managed_mods)
    
    if future_mc_version && future_mc_version != mc_version
      future_updates = []
      CLI::UI::Progress.progress do |bar|
        managed_mods.each_with_index do |mod, i|
          bar.tick(set_percent: (i + 1).to_f / managed_mods.length)
          latest_version = find_latest_version(mod.project_id, future_mc_version)
          if latest_version
            future_updates << { mod_name: mod.name, version: latest_version[:version_number] }
          end
        end
      end
      
      if future_updates.length == managed_mods.length
        puts CLI::UI.fmt("\n{{green:✓}} All mods support updating to Minecraft {{bold:#{future_mc_version}}}")
        future_updates.each do |update|
          puts CLI::UI.fmt("  {{gray:•}} {{cyan:#{update[:mod_name]}}} can be updated to v#{update[:version]}")
        end
      else
        puts CLI::UI.fmt("\n{{yellow:⚠}} Not all mods support a common future Minecraft version.")
      end
    end
  end
end

def handle_update
  CLI::UI::Frame.open("Mod Updates") do
    # Get all managed mods and check for updates
    managed_mods = get_all_managed_mods
    mc_version = get_minecraft_version(managed_mods)
    
    updates_available = []
    CLI::UI::Progress.progress do |bar|
      managed_mods.each_with_index do |mod, i|
        bar.tick(set_percent: (i + 1).to_f / managed_mods.length)
        latest_version = find_latest_version(mod.project_id, mc_version)
        if latest_version && latest_version[:version_number] != mod.installed_info[:version]
          updates_available << { managed_mod: mod, new_mod: latest_version }
        end
      end
    end
    
    if updates_available.empty?
      puts CLI::UI.fmt("{{green:✓}} All mods are up to date.")
      return
    end
    
    puts CLI::UI.fmt("\n{{yellow:🔄}} Updates available:")
    updates_available.each_with_index do |update, i|
      type_label = update[:managed_mod].type == :server_only ? 'Server-Only' : 'CLIENT UPDATE REQUIRED'
      type_color = update[:managed_mod].type == :server_only ? 'green' : 'red'
      old_version = update[:managed_mod].installed_info[:version]
      puts CLI::UI.fmt("  {{bold:#{i + 1}.}} {{cyan:#{update[:managed_mod].name}}} ({{#{type_color}:#{type_label}}})")
      puts CLI::UI.fmt("      {{yellow:#{old_version}}} → {{green:#{update[:new_mod][:version_number]}}}")
    end
    
    selected_updates = CLI::UI::Prompt.ask("Which mods would you like to update?") do |handler|
      handler.option("all") { updates_available }
      handler.option("none") { [] }
      handler.option("custom") do
        CLI::UI::Prompt.multi_select("Select mods to update", options: updates_available.map { |u| u[:managed_mod].name })
      end
    end
    
    if selected_updates.empty?
      puts CLI::UI.fmt("{{info:No mods selected for update.}}")
      return
    end
    
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    
    # Perform dry run first
    proceed = perform_dry_run(selected_updates, timestamp)
    unless proceed
      puts CLI::UI.fmt("{{info:Update cancelled by user.}}")
      return
    end
    
    # Actual update process
    puts CLI::UI.fmt("{{blue:🚀}} Applying mod updates...")
    
    # 1. Stop server
    puts CLI::UI.fmt("{{red:🛑}} Stopping Minecraft server...")
    unless run_server_command('stop')
      puts CLI::UI.fmt("{{red:✗}} Could not stop server. Aborting update.")
      exit 1
    end
    
    # 2. Create backup directory for this session
    session_backup_dir = File.join(CONFIG[:backup_dir], "backup_#{timestamp}")
    FileUtils.mkdir_p(session_backup_dir)
    
    completed_operations = []
    server_started = false
    
    begin
      CLI::UI::Progress.progress do |bar|
        selected_updates.each_with_index do |update, i|
          bar.tick(set_percent: (i + 1).to_f / selected_updates.length)
          
          old_path = update[:managed_mod].installed_info[:path]
          new_path = File.join(CONFIG[:mods_dir], update[:new_mod][:filename])
          backup_path = File.join(session_backup_dir, File.basename(old_path))
          
          puts CLI::UI.fmt("  {{blue:•}} Updating {{cyan:#{update[:managed_mod].name}}}...")
          
          begin
            # 1. Backup existing mod
            FileUtils.mv(old_path, backup_path)
            
            # 2. Download new mod
            download_file(update[:new_mod][:url], new_path)
            
            old_version = update[:managed_mod].installed_info[:version]
            new_version = update[:new_mod][:version_number]
            mod_name = update[:managed_mod].name
            puts CLI::UI.fmt("    {{green:✓}} Updated {{cyan:#{mod_name}}} from {{yellow:#{old_version}}} to {{green:#{new_version}}}")
            
            completed_operations << {
              type: :update,
              mod_name: update[:managed_mod].name,
              backup_path: backup_path,
              new_path: new_path
            }
            
          rescue => e
            puts CLI::UI.fmt("    {{red:✗}} Failed to update #{update[:managed_mod].name}: #{e.message}")
            
            # Attempt to restore from backup if something went wrong
            if File.exist?(backup_path) && !File.exist?(old_path)
              begin
                FileUtils.mv(backup_path, old_path)
                puts CLI::UI.fmt("    {{green:✓}} Restored from backup.")
              rescue
                puts CLI::UI.fmt("    {{red:✗}} CRITICAL: Failed to restore from backup. Manual intervention required.")
              end
            end
            
            # If new file was partially downloaded, clean it up
            if File.exist?(new_path)
              begin
                File.delete(new_path)
              rescue
                # ignore
              end
            end
            
            continue = CLI::UI::Prompt.confirm("Continue with remaining updates?")
            break unless continue
          end
        end
      end
      
    rescue => e
      puts CLI::UI.fmt("\n{{red:✗}} An unexpected error occurred during the update process: #{e.message}")
      puts CLI::UI.fmt("{{yellow:💡}} Attempting to revert any changes made during this session...")
      
      # Revert successful operations from this session
      if completed_operations.any?
        puts CLI::UI.fmt("{{yellow:🔄}} Reverting #{completed_operations.length} completed operation(s)...")
        completed_operations.reverse_each do |op|
          case op[:type]
          when :update
            puts CLI::UI.fmt("  {{blue:•}} Reverting update for {{cyan:#{op[:mod_name]}}}...")
            # Delete the new file
            File.delete(op[:new_path]) if File.exist?(op[:new_path])
            # Restore from backup
            FileUtils.mv(op[:backup_path], File.join(CONFIG[:mods_dir], File.basename(op[:backup_path])))
          end
        end
      end
      
    ensure
      # Always try to restart the server
      puts CLI::UI.fmt("\n{{green:🔄}} Starting Minecraft server...")
      server_started = run_server_command('start')
      
      if server_started
        puts CLI::UI.fmt("{{green:🎮}} Server started successfully! Happy gaming!")
      else
        puts CLI::UI.fmt("{{red:⚠}} Server failed to start. Please check server logs and start manually.")
      end
    end
  end
end

def handle_revert
  CLI::UI::Frame.open("Mod Revert") do
    puts CLI::UI.fmt("{{yellow:🔄}} Uh oh, something went wrong? Let's roll it back.")
    
    backup_dirs = Dir.glob(File.join(CONFIG[:backup_dir], 'backup_*')).sort
    if backup_dirs.empty?
      puts CLI::UI.fmt("{{red:✗}} No backups found to revert to.")
      return
    end
    
    puts CLI::UI.fmt("\n{{yellow:📋}} Available backups (newest first):")
    backup_dirs.reverse.each_with_index do |backup_dir, i|
      puts CLI::UI.fmt("  {{bold:#{i + 1}.}} #{File.basename(backup_dir)}")
    end
    
    backup_choice = CLI::UI::Prompt.ask("Which backup would you like to revert to?") do |handler|
      backup_dirs.reverse.each_with_index do |backup_dir, i|
        handler.option((i + 1).to_s) { backup_dir }
      end
      handler.option("cancel") { nil }
    end
    
    if backup_choice.nil?
      puts CLI::UI.fmt("{{info:Revert cancelled.}}")
      return
    end
    
    selected_backup_dir = backup_choice
    
    puts CLI::UI.fmt("\n{{blue:🚀}} Reverting to backup: {{underline:#{File.basename(selected_backup_dir)}}}")
    
    # 1. Stop server
    puts CLI::UI.fmt("{{red:🛑}} Stopping Minecraft server...")
    unless run_server_command('stop')
      puts CLI::UI.fmt("{{red:✗}} Could not stop server. Aborting revert.")
      exit 1
    end
    
    server_started = false
    begin
      # Get a list of currently managed mods to match against backup files
      managed_mods = get_all_managed_mods
      
      # 2. Clear current mods directory of managed mods
      puts CLI::UI.fmt("{{yellow:🧹}} Clearing current managed mods...")
      managed_mods.each do |mod|
        FileUtils.rm_f(mod.installed_info[:path])
      end
      
      # 3. Restore from backup
      puts CLI::UI.fmt("{{green:🔄}} Restoring mods from backup...")
      backup_jars = Dir.glob(File.join(selected_backup_dir, '*.jar'))
      reverted_mods = []
      errors = []
      
      CLI::UI::Progress.progress do |bar|
        backup_jars.each_with_index do |backup_jar_path, i|
          bar.tick(set_percent: (i + 1).to_f / backup_jars.length)
          
          begin
            # Try to find a matching managed mod to be smart about it
            filename = File.basename(backup_jar_path)
            matching_mod = managed_mods.find do |mod|
              filename.match?(Regexp.new(mod.filename_pattern, Regexp::IGNORECASE))
            end
            
            if matching_mod
              puts CLI::UI.fmt("  {{blue:•}} Restoring {{cyan:#{matching_mod.name}}}...")
              
              destination_path = File.join(CONFIG[:mods_dir], filename)
              FileUtils.cp(backup_jar_path, destination_path)
              
              unless File.exist?(destination_path)
                errors << "Failed to restore #{filename}"
                next
              end
              
              reverted_mods << filename
            else
              puts CLI::UI.fmt("    {{yellow:⚠}} Could not match backup file to any managed mod, restoring anyway...")
              
              destination_path = File.join(CONFIG[:mods_dir], filename)
              FileUtils.cp(backup_jar_path, destination_path)
              
              unless File.exist?(destination_path)
                errors << "Failed to restore #{filename}"
                next
              end
              
              reverted_mods << filename
            end
            
          rescue => e
            errors << "#{filename}: #{e.message}"
          end
        end
      end
      
      puts CLI::UI.fmt("\n{{green:✓}} Reverted mods: #{reverted_mods.join(', ')}")
      if errors.any?
        puts CLI::UI.fmt("{{red:✗}} Errors during revert:")
        errors.each { |e| puts CLI::UI.fmt("  {{red:•}} #{e}") }
      end
      
    rescue => e
      puts CLI::UI.fmt("\n{{red:✗}} Critical error during revert: #{e.message}")
    ensure
      # Always try to restart the server
      puts CLI::UI.fmt("\n{{green:🔄}} Starting Minecraft server...")
      server_started = run_server_command('start')
      
      if server_started
        puts CLI::UI.fmt("{{green:🎮}} Reverted to backup: {{bold:#{File.basename(selected_backup_dir)}}}")
      else
        puts CLI::UI.fmt("{{red:⚠}} Server failed to start. Please check server logs and start manually.")
      end
    end
  end
end

def get_dependents(project_id, managed_mods)
  # Find all mods that depend on the given project_id
  managed_mods.select { |mod| mod.depends_on.include?(project_id) }
end

def get_dependency_chain(mod, managed_mods, visited = [])
  # Get the full dependency chain for a mod (recursive)
  return [] if visited.include?(mod.project_id)
  visited << mod.project_id
  
  dependencies = []
  mod.depends_on.each do |dep_id|
    dep_mod = managed_mods.find { |m| m.project_id == dep_id }
    if dep_mod
      dependencies << dep_mod
      dependencies.concat(get_dependency_chain(dep_mod, managed_mods, visited))
    end
  end
  
  dependencies.uniq { |m| m.project_id }
end

def analyze_removal_impact(mod, managed_mods)
  # Analyze what would break if this mod was removed
  direct_dependents = get_dependents(mod.project_id, managed_mods)
  
  # Find indirect dependents (mods that depend on the direct dependents)
  indirect_dependents = []
  direct_dependents.each do |dependent|
    indirect_dependents.concat(get_dependents(dependent.project_id, managed_mods))
  end
  
  {
    direct: direct_dependents,
    indirect: indirect_dependents.uniq { |m| m.project_id } - direct_dependents
  }
end

def handle_max_version
  # Checks the maximum Minecraft version supported by all mods
  managed_mods = get_all_managed_mods
  
  CLI::UI::Frame.open("Maximum Minecraft Version Analysis") do
    puts CLI::UI.fmt("{{blue:🔍}} Analyzing maximum Minecraft version support across all mods...")
    
    if managed_mods.empty?
      puts CLI::UI.fmt("{{info:No managed mods found.}}")
      return
    end
    
    mod_version_data = []
    
    CLI::UI::Progress.progress do |bar|
      managed_mods.each_with_index do |mod, i|
        bar.tick(set_percent: (i + 1).to_f / managed_mods.length)
        
        # Get all supported Minecraft versions for this mod
        supported_versions = get_all_minecraft_versions_for_mod(mod.project_id)
        
        # Find the highest version this mod supports
        max_version = nil
        if supported_versions.any?
          # Sort versions and get the latest (only considering release versions)
          release_versions = supported_versions.select { |v| is_release_version(v) }
          if release_versions.any?
            sorted_versions = release_versions.sort_by { |v| v.split('.').map(&:to_i) }
            max_version = sorted_versions.last
          end
        end
        
        mod_version_data << {
          mod: mod,
          max_version: max_version,
          all_versions: supported_versions
        }
      end
    end
    
    # Sort mods by their maximum supported version (lowest first to identify blockers)
    mod_version_data.sort_by! do |data|
      if data[:max_version]
        data[:max_version].split('.').map(&:to_i)
      else
        [0, 0, 0] # Put mods with no version data at the beginning
      end
    end
    
    # Find the overall maximum version that ALL mods support (only release versions)
    all_versions_intersection = mod_version_data.map { |data| data[:all_versions] }.reduce(:&)
    overall_max = nil
    if all_versions_intersection && all_versions_intersection.any?
      release_intersection = all_versions_intersection.select { |v| is_release_version(v) }
      if release_intersection.any?
        sorted_common = release_intersection.sort_by { |v| v.split('.').map(&:to_i) }
        overall_max = sorted_common.last
      end
    end
    
    # Display results
    puts CLI::UI.fmt("\n{{bold:📊 Maximum Minecraft Version Analysis}}")
    
    if overall_max
      puts CLI::UI.fmt("{{green:✓}} Maximum version ALL mods support: {{bold:#{overall_max}}}")
    else
      puts CLI::UI.fmt("{{red:✗}} No common Minecraft version found across all mods")
    end
    
    # Find the absolute highest version any mod supports (only release versions)
    highest_individual = mod_version_data.map { |data| data[:max_version] }.compact
    release_individual = highest_individual.select { |v| is_release_version(v) }
    if release_individual.any?
      absolute_max = release_individual.sort_by { |v| v.split('.').map(&:to_i) }.last
      puts CLI::UI.fmt("{{blue:🚀}} Highest release version any mod supports: {{bold:#{absolute_max}}}")
    end
    
    puts CLI::UI.fmt("\n{{bold:📋 Per-Mod Maximum Versions:}}")
    
    # Group mods by their maximum supported version
    version_groups = mod_version_data.group_by { |data| data[:max_version] }
    
    version_groups.each do |max_ver, mods_data|
      if max_ver.nil?
        puts CLI::UI.fmt("\n{{red:❌ Unknown/No Version Data:}}")
        mods_data.each do |data|
          puts CLI::UI.fmt("  {{gray:•}} {{cyan:#{data[:mod].name}}} (Project: #{data[:mod].project_id})")
        end
      else
        version_color = if overall_max && max_ver == overall_max
          "green"
        elsif highest_individual.any? && max_ver == absolute_max
          "blue"
        else
          "yellow"
        end
        
        puts CLI::UI.fmt("\n{{#{version_color}:📌 Minecraft #{max_ver}:}} (#{mods_data.length} mod#{'s' if mods_data.length != 1})")
        mods_data.each do |data|
          type_label = data[:mod].type == :server_only ? 'Server-Only' : 'Client+Server'
          type_color = data[:mod].type == :server_only ? 'green' : 'blue'
          platform_indicator = data[:mod].is_platform ? ' {{yellow:[PLATFORM]}}' : ''
          dependents_count = get_dependents(data[:mod].project_id, managed_mods).length
          dependents_info = dependents_count > 0 ? " {{gray:(#{dependents_count} dependent#{'s' if dependents_count != 1})}}" : ''
          puts CLI::UI.fmt("  {{gray:•}} {{cyan:#{data[:mod].name}}} ({{#{type_color}:#{type_label}}})#{platform_indicator}#{dependents_info}")
        end
      end
    end
    
    # Show upgrade potential
    current_mc = begin
      get_minecraft_version(managed_mods)
    rescue
      nil
    end
    
    if current_mc && overall_max && current_mc != overall_max
      puts CLI::UI.fmt("\n{{yellow:🔄 Upgrade Potential:}}")
      puts CLI::UI.fmt("  Current: {{yellow:#{current_mc}}}")
      puts CLI::UI.fmt("  Possible: {{green:#{overall_max}}}")
      
      # Show which mods would prevent going higher
      if highest_individual.any?
        absolute_max = highest_individual.sort_by { |v| v.split('.').map(&:to_i) }.last
        if absolute_max != overall_max
          blocking_mods = mod_version_data.select { |data| data[:max_version] == overall_max }
          puts CLI::UI.fmt("  Blocked by: {{red:#{blocking_mods.map { |data| data[:mod].name }.join(', ')}}}")
          
          # Find the next highest version that some mods actually support
          all_supported_versions = mod_version_data.map { |data| data[:max_version] }.compact.uniq
          release_versions = all_supported_versions.select { |v| is_release_version(v) }
          
          if release_versions.any?
            sorted_versions = release_versions.sort_by { |v| v.split('.').map(&:to_i) }
            overall_max_parts = overall_max.split('.').map(&:to_i)
            
            # Find the next version higher than overall_max (what's blocking us)
            next_version = sorted_versions.find do |version|
              version_parts = version.split('.').map(&:to_i)
              # Use spaceship operator for safe array comparison
              (version_parts <=> overall_max_parts) == 1
            end
            
            if next_version
              puts CLI::UI.fmt("  Could reach: {{blue:#{next_version}}} if these blocking mods were updated/replaced")
            else
              puts CLI::UI.fmt("  Already at highest available version among managed mods")
            end
          end
        end
      end
    elsif current_mc && overall_max && current_mc == overall_max
      puts CLI::UI.fmt("\n{{green:✓}} You're already at the maximum supported version!")
      
      # Still show next possible version if available
      if highest_individual.any?
        absolute_max = highest_individual.sort_by { |v| v.split('.').map(&:to_i) }.last
        if absolute_max != overall_max
          all_supported_versions = mod_version_data.map { |data| data[:max_version] }.compact.uniq
          release_versions = all_supported_versions.select { |v| is_release_version(v) }
          
          if release_versions.any?
            sorted_versions = release_versions.sort_by { |v| v.split('.').map(&:to_i) }
            current_mc_parts = current_mc.split('.').map(&:to_i)
            
            next_version = sorted_versions.find do |version|
              version_parts = version.split('.').map(&:to_i)
              # Use spaceship operator for safe array comparison
              (version_parts <=> current_mc_parts) == 1
            end
            
            if next_version
              blocking_mods = mod_version_data.select { |data| data[:max_version] == current_mc }
              puts CLI::UI.fmt("  Next possible: {{blue:#{next_version}}} if {{red:#{blocking_mods.map { |data| data[:mod].name }.join(', ')}}} were updated")
            end
          end
        end
      end
    end
    
    # Show dependency analysis
    puts CLI::UI.fmt("\n{{bold:🔗 Dependency Analysis:}}")
    
    platform_mods = managed_mods.select { |mod| mod.is_platform }
    regular_mods = managed_mods.reject { |mod| mod.is_platform }
    
    puts CLI::UI.fmt("{{yellow:📚 Platform Mods:}} #{platform_mods.length} total")
    platform_mods.each do |mod|
      dependents = get_dependents(mod.project_id, managed_mods)
      puts CLI::UI.fmt("  {{cyan:#{mod.name}}} → {{gray:#{dependents.length} dependent#{'s' if dependents.length != 1}}}")
      if dependents.length > 0 && dependents.length <= 3
        dependents.each { |dep| puts CLI::UI.fmt("    {{gray:• #{dep.name}}}") }
      elsif dependents.length > 3
        dependents.first(3).each { |dep| puts CLI::UI.fmt("    {{gray:• #{dep.name}}}") }
        puts CLI::UI.fmt("    {{gray:• ... and #{dependents.length - 3} more}}")
      end
    end
    
    puts CLI::UI.fmt("\n{{blue:🔧 Regular Mods:}} #{regular_mods.length} total")
    orphaned_mods = regular_mods.select { |mod| mod.depends_on.empty? }
    if orphaned_mods.any?
      puts CLI::UI.fmt("  {{gray:Independent mods (no dependencies):}} #{orphaned_mods.length}")
    end
    
    # Show removal impact for platform mods that are preventing upgrades
    if overall_max && highest_individual.any?
      absolute_max = highest_individual.sort_by { |v| v.split('.').map(&:to_i) }.last
      if absolute_max != overall_max
        blocking_mods = mod_version_data.select { |data| data[:max_version] == overall_max }
        platform_blockers = blocking_mods.select { |data| data[:mod].is_platform }
        
        if platform_blockers.any?
          puts CLI::UI.fmt("\n{{red:⚠️  Removal Impact Analysis:}}")
          puts CLI::UI.fmt("These platform mods are preventing upgrade to #{absolute_max}:")
          
          platform_blockers.each do |data|
            impact = analyze_removal_impact(data[:mod], managed_mods)
            total_impact = impact[:direct].length + impact[:indirect].length
            puts CLI::UI.fmt("  {{red:#{data[:mod].name}}} → would break {{red:#{total_impact}}} mod#{'s' if total_impact != 1}")
            
            if impact[:direct].any?
              puts CLI::UI.fmt("    {{gray:Direct:}} #{impact[:direct].map(&:name).join(', ')}")
            end
            if impact[:indirect].any?
              puts CLI::UI.fmt("    {{gray:Indirect:}} #{impact[:indirect].map(&:name).join(', ')}")
            end
          end
        end
      end
    end
    
    # Show platform mods that could potentially be removed
    puts CLI::UI.fmt("\n{{yellow:🗑️  Platform Mods - Removal Candidates:}}")
    unused_platform_mods = platform_mods.select do |mod|
      dependents = get_dependents(mod.project_id, managed_mods)
      dependents.empty?
    end
    
    if unused_platform_mods.any?
      puts CLI::UI.fmt("{{yellow:⚠️}} Found {{bold:#{unused_platform_mods.length}}} platform mod#{'s' if unused_platform_mods.length != 1} with no dependents:")
      unused_platform_mods.each do |mod|
        mod_data = mod_version_data.find { |data| data[:mod].project_id == mod.project_id }
        max_version_info = mod_data && mod_data[:max_version] ? " (max: #{mod_data[:max_version]})" : ""
        type_label = mod.type == :server_only ? 'Server-Only' : 'Client+Server'
        type_color = mod.type == :server_only ? 'green' : 'blue'
        puts CLI::UI.fmt("  {{red:•}} {{cyan:#{mod.name}}} ({{#{type_color}:#{type_label}}})#{max_version_info}")
        puts CLI::UI.fmt("    {{gray:→ May be unused}}")
      end
      puts CLI::UI.fmt("\n{{gray:💡 Note: These platform mods are not required by any other managed mods.}}")
      puts CLI::UI.fmt("{{gray:   However, verify they're not needed by unmanaged mods before removal.}}")
    else
      puts CLI::UI.fmt("{{green:✓}} All platform mods are being used by other mods")
    end
  end
end

def handle_deps
  # Show dependencies for a specific mod
  mod_name = ARGV[1]
  unless mod_name
    puts CLI::UI.fmt("{{red:✗}} Please specify a mod name: #{$0} deps <mod_name>")
    exit 1
  end
  
  managed_mods = get_all_managed_mods
  target_mod = managed_mods.find { |mod| mod.name.downcase.include?(mod_name.downcase) }
  
  unless target_mod
    puts CLI::UI.fmt("{{red:✗}} Mod not found: #{mod_name}")
    puts CLI::UI.fmt("Available mods: #{managed_mods.map(&:name).join(', ')}")
    exit 1
  end
  
  CLI::UI::Frame.open("Dependencies for #{target_mod.name}") do
    dependents = get_dependents(target_mod.project_id, managed_mods)
    
    puts CLI::UI.fmt("{{bold:#{target_mod.name}}} ({{cyan:#{target_mod.project_id}}})")
    puts CLI::UI.fmt("{{gray:Type:}} #{target_mod.type.to_s.gsub('_', '-')}")
    puts CLI::UI.fmt("{{gray:Platform:}} #{target_mod.is_platform ? 'Yes' : 'No'}")
    
    if dependents.any?
      puts CLI::UI.fmt("\n{{yellow:🔗 Mods that depend on this:}} (#{dependents.length})")
      dependents.each do |dependent|
        puts CLI::UI.fmt("  {{cyan:#{dependent.name}}} (#{dependent.type.to_s.gsub('_', '-')})")
      end
      
      if target_mod.is_platform
        puts CLI::UI.fmt("\n{{red:⚠️  Removing this platform mod would break #{dependents.length} mod#{'s' if dependents.length != 1}!}}")
      end
    else
      puts CLI::UI.fmt("\n{{green:✓}} No mods depend on this - safe to remove")
    end
    
    if target_mod.depends_on.any?
      puts CLI::UI.fmt("\n{{blue:📦 This mod depends on:}}")
      target_mod.depends_on.each do |dep_id|
        dep_mod = managed_mods.find { |m| m.project_id == dep_id }
        if dep_mod
          puts CLI::UI.fmt("  {{cyan:#{dep_mod.name}}} (#{dep_mod.type.to_s.gsub('_', '-')})")
        else
          puts CLI::UI.fmt("  {{red:#{dep_id}}} (not found in managed mods)")
        end
      end
    end
  end
end

def handle_platforms
  # List all platform mods and their dependents
  managed_mods = get_all_managed_mods
  platform_mods = managed_mods.select { |mod| mod.is_platform }
  
  CLI::UI::Frame.open("Platform Mods Analysis") do
    if platform_mods.empty?
      puts CLI::UI.fmt("{{info:No platform mods found.}}")
      return
    end
    
    puts CLI::UI.fmt("{{bold:Platform Mods (#{platform_mods.length} total)}}")
    
    # Separate platform mods into used and unused
    unused_platform_mods = []
    used_platform_mods = []
    
    platform_mods.each do |mod|
      dependents = get_dependents(mod.project_id, managed_mods)
      if dependents.empty?
        unused_platform_mods << mod
      else
        used_platform_mods << mod
      end
    end
    
    # Show used platform mods first
    if used_platform_mods.any?
      puts CLI::UI.fmt("\n{{green:✓ Active Platform Mods (#{used_platform_mods.length}):}}")
      used_platform_mods.sort_by { |mod| -get_dependents(mod.project_id, managed_mods).length }.each do |mod|
        dependents = get_dependents(mod.project_id, managed_mods)
        puts CLI::UI.fmt("\n{{cyan:#{mod.name}}} ({{yellow:#{mod.project_id}}})")
        puts CLI::UI.fmt("  {{gray:Type:}} #{mod.type.to_s.gsub('_', '-')}")
        puts CLI::UI.fmt("  {{gray:Dependents:}} #{dependents.length}")
        
        dependents.each do |dependent|
          puts CLI::UI.fmt("    {{gray:•}} #{dependent.name}")
        end
      end
    end
    
    # Highlight unused platform mods as removal candidates
    if unused_platform_mods.any?
      puts CLI::UI.fmt("\n{{red:⚠️  Unused Platform Mods - Removal Candidates (#{unused_platform_mods.length}):}}")
      unused_platform_mods.each do |mod|
        puts CLI::UI.fmt("\n{{red:#{mod.name}}} ({{yellow:#{mod.project_id}}})")
        puts CLI::UI.fmt("  {{gray:Type:}} #{mod.type.to_s.gsub('_', '-')}")
        puts CLI::UI.fmt("  {{red:No dependents - can potentially be removed}}")
        puts CLI::UI.fmt("  {{gray:→ Consider removing to simplify mod management}}")
      end
      puts CLI::UI.fmt("\n{{gray:💡 Note: Verify these aren't needed by unmanaged mods before removal.}}")
    else
      puts CLI::UI.fmt("\n{{green:✓ All platform mods are being used by other mods}}")
    end
  end
end

def handle_impact
  # Show the full impact of removing a mod
  mod_name = ARGV[1]
  unless mod_name
    puts CLI::UI.fmt("{{red:✗}} Please specify a mod name: #{$0} impact <mod_name>")
    exit 1
  end
  
  managed_mods = get_all_managed_mods
  target_mod = managed_mods.find { |mod| mod.name.downcase.include?(mod_name.downcase) }
  
  unless target_mod
    puts CLI::UI.fmt("{{red:✗}} Mod not found: #{mod_name}")
    puts CLI::UI.fmt("Available mods: #{managed_mods.map(&:name).join(', ')}")
    exit 1
  end
  
  CLI::UI::Frame.open("Removal Impact for #{target_mod.name}") do
    impact = analyze_removal_impact(target_mod, managed_mods)
    total_impact = impact[:direct].length + impact[:indirect].length
    
    puts CLI::UI.fmt("{{bold:#{target_mod.name}}}")
    puts CLI::UI.fmt("{{gray:Platform:}} #{target_mod.is_platform ? 'Yes' : 'No'}")
    
    if total_impact == 0
      puts CLI::UI.fmt("\n{{green:✓ SAFE TO REMOVE}} - No other mods depend on this")
    else
      puts CLI::UI.fmt("\n{{red:⚠️  REMOVAL IMPACT: #{total_impact} mod#{'s' if total_impact != 1} would be affected}}")
      
      if impact[:direct].any?
        puts CLI::UI.fmt("\n{{red:Direct dependencies (#{impact[:direct].length}):}}")
        impact[:direct].each do |mod|
          puts CLI::UI.fmt("  {{red:✗}} {{cyan:#{mod.name}}} would break immediately")
        end
      end
      
      if impact[:indirect].any?
        puts CLI::UI.fmt("\n{{yellow:Indirect dependencies (#{impact[:indirect].length}):}}")
        impact[:indirect].each do |mod|
          puts CLI::UI.fmt("  {{yellow:⚠}} {{cyan:#{mod.name}}} depends on the broken mods")
        end
      end
      
      puts CLI::UI.fmt("\n{{red:Recommendation:}} Do not remove this mod without replacing it or removing dependents first")
    end
  end
end

def main
  CLI::UI::StdoutRouter.enable
  
  # Simple command-line argument parsing
  command = ARGV[0]
  
  # Always validate config first
  validate_config
  
  # Always clean up old backups
  cleanup_old_backups
  
  CLI::UI::Frame.open("Minecraft Mod Manager v5.0.0 - YAML Configuration Based", color: :blue) do
    begin
      case command
      when 'list'
        handle_list_mods
      when 'check'
        handle_check_updates
      when 'update'
        handle_update
      when 'revert'
        handle_revert
      when 'max-version'
        handle_max_version
      when 'deps'
        handle_deps
      when 'platforms'
        handle_platforms
      when 'impact'
        handle_impact
      else
        puts CLI::UI.fmt("{{red:✗}} Unknown command: #{command}")
        puts "Usage: #{$0} [list|check|update|revert|max-version|deps <mod_name>|platforms|impact <mod_name>]"
        exit 1
      end
    rescue StandardError => e
      puts CLI::UI.fmt("{{red:✗}} An unexpected error occurred: #{e.message}")
      puts CLI::UI.fmt("{{gray:💡}} Run in debug mode with DEBUG=1 for full stack trace.")
      exit 1
    end
  end
end

main
