require 'yaml'
require 'zip'
require 'json'
require 'mods/modrinth'
require 'mods/minecraft_version'
require 'utility/yaml'
require 'mods/updater'

module Mods
  ModDeclaration = Data.define(
    :project_id,
    :name,
    :type,
    :filename_pattern,
    :depends_on,
    :is_platform,
    :optional
  ) do
    def supported_minecraft_versions(mod_loader: nil)
      Mods::Modrinth.fetch_supported_versions(project_id, mod_loader: mod_loader)
    end

    def maximum_supported_minecraft_version(mod_loader: nil)
      supported_minecraft_versions(mod_loader:).last
    end

    def platform? = is_platform
    def optional? = optional == true
    def required? = !optional?

    def to_h
      super { |name, val| [name.to_s, val] }
    end
  end

  InstalledMod = Data.define(
    :declaration,
    :version,
    :filename,
    :filepath,
    :minecraft_version
  )

  VersionInfo = Data.define(
    :version,
    :minecraft_version
  )

  UNKNOWN_VERSION = VersionInfo.new(nil, nil)
  
  class ModConfig
    YAML_CONFIG_FILE = 'mcpm.yml'

    Error = Class.new(StandardError)
    DeclarationError = Class.new(Error)
    MissingModError = Class.new(Error)
    AmbiguousModError = Class.new(Error)
    REQUIRED_FIELDS = %w[project_id name type filename_pattern].freeze

    attr_reader :base_dir

    def initialize(base_dir)
      self.base_dir = base_dir
    end

    def mods_dir
      @mods_dir ||= File.join(base_dir, 'mods')
    end

    def jar_files
      @jar_files ||= Dir.glob(File.join(mods_dir, '*.jar'))
    end

    def mod_loader
      loader = config_data['loader']
      raise DeclarationError, "Missing 'loader' in #{YAML_CONFIG_FILE}" unless loader

      loader.downcase
    end

    def minecraft_version
      version = config_data['minecraft_version']
      raise DeclarationError, "Missing 'minecraft_version' in #{YAML_CONFIG_FILE}" unless version

      MinecraftVersion.new(version)
    end

    def mod_declarations
      @mod_declarations ||= load_mod_declarations
    end

    def find_installed_mod_by_id(mod_id)
      declaration = mod_declarations.find { |mod| mod.project_id.casecmp?(mod_id) }
      declaration && find_installed_mod(declaration)
    end

    def find_installed_mod_by_name(mod_name)
      declaration = mod_declarations.find { |mod| mod.name.casecmp?(mod_name) }
      declaration && find_installed_mod(declaration)
    end

    def to_h
      config_data
    end

    def dependents_of(mod)
      return [] unless mod.platform?

      declaration = if mod.is_a?(InstalledMod)
        mod.declaration
      elsif mod.is_a?(ModDeclaration)
        mod
      else
        raise ArgumentError, "Expected InstalledMod or ModDeclaration, got #{mod.class}"
      end

      @dependents_of ||= {}
      @dependents_of[declaration.project_id] ||= begin
        mod_declarations.select { |decl| decl.depends_on.include?(declaration.project_id) }
      end
    end

    def next_available_version(mod_declaration)
      supported_versions = Modrinth.fetch_available_versions(
        mod_declaration.project_id,
        mod_loader:,
        minecraft_version:
      )

      if supported_versions.empty?
        alternate_version = MinecraftVersion.compatible_version(minecraft_version)
        supported_versions = Modrinth.fetch_available_versions(
          mod_declaration.project_id,
          mod_loader:,
          minecraft_version: alternate_version
        ) if alternate_version
      end

      supported_versions.first&.version
    end

    def can_update?(installed_mod)
      # TODO: Version comparison with installed is shoddy, e.g.:
      # > Mod 'Open Parties and Claims' can be updated from 0.25.7 to fabric-1.21.10-0.25.7.
      next_available_version(installed_mod.declaration) != installed_mod.version
    end

    def find_installed_mod(mod_declaration)
      pattern = Regexp.new(mod_declaration.filename_pattern, Regexp::IGNORECASE)
      matching_jars = jar_files.select { |jar| File.basename(jar) =~ pattern }

      if matching_jars.empty?
        raise MissingModError, "#{mod_declaration.name} JAR file not found (#{mod_declaration.filename_pattern})"
      elsif matching_jars.size > 1
        raise AmbiguousModError, "Multiple JAR files match pattern for mod: #{mod_declaration.name} (#{matching_jars.map { |j| File.basename(j) }.join(', ')})"
      else
        jar_path = matching_jars.first
        
        version_info = version_from_jar(jar_path)
        InstalledMod.new(
          declaration: mod_declaration,
          version: version_info.version,
          filename: File.basename(jar_path),
          filepath: jar_path,
          minecraft_version: version_info.minecraft_version,
        )
      end
    end

    def update_game_version!(new_version)
      new_config = config_data.dup
      new_config['minecraft_version'] = new_version.to_s

       # Invalidate cache
      @config_data = nil

      Utility::YAML.dump_to_file(new_config, filepath: File.join(base_dir, YAML_CONFIG_FILE))
    end

    def install_mod!(mod_declaration)
      FileUtils.mkdir_p(mods_dir) unless Dir.exist?(mods_dir)
      updater = Mods::Updater.new(self, mods_dir, minecraft_version)
      updater.download_mod(mod_declaration)
      
       # Invalidate cache
      @mod_declarations = nil
      @config_data = nil
    end

    def update_mod!(installed_mod)
      unless find_installed_mod(installed_mod.declaration)
        raise MissingModError, "Mod #{installed_mod.declaration.name} not installed"
      end
      
      install_mod!(installed_mod.declaration) if can_update?(installed_mod)
      FileUtils.remove([installed_mod.filepath])
    end

    def add_mod!(mod_declaration)
      if mod_declarations.find { |mod| mod.project_id == mod_declaration.project_id }
        raise DeclarationError, "Mod `#{mod_declaration.name}` already in configuration"
      end

      new_config = config_data.dup
      new_config['mods'] << mod_declaration.to_h

      Utility::YAML.dump_to_file(new_config, filepath: File.join(base_dir, YAML_CONFIG_FILE))

      install_mod!(mod_declaration)
    end

    private

    attr_writer :base_dir

    def config_data
      @config_data ||= begin
        yaml = File.join(base_dir, YAML_CONFIG_FILE)
        unless File.exist?(yaml)
          puts "No #{YAML_CONFIG_FILE} found in #{base_dir}"
          exit 1
        end

        config_data = YAML.safe_load_file(yaml)

        unless config_data.is_a?(Hash) && config_data['mods'].is_a?(Array)
          raise DeclarationError, "Invalid configuration format of mods.yml in #{base_dir}. Expected a 'mods' key with an array of mod declarations."
        end

        config_data
      end
    end

    def version_from_jar(jar_path)
      begin
        Zip::File.open(jar_path) do |zip_file|
          entry = zip_file.find_entry('fabric.mod.json')
          return UNKNOWN_VERSION unless entry

          raw_content = entry.get_input_stream.read
          cleaned_content = raw_content.gsub(/[\x00-\x1F\x7F]/, '')
          json_data = JSON.parse(cleaned_content)
          
          VersionInfo.new(
            version: json_data['version'],
            minecraft_version: json_data.dig('depends', 'minecraft')
          )
        end
      rescue
        UNKNOWN_VERSION
      end
    end

    def load_mod_declarations
      config_data['mods'].map do |mod_data|
        validate_yaml_declaration!(mod_data)
        ModDeclaration.new(
          project_id: mod_data['project_id'],
          name: mod_data['name'],
          type: mod_data['type'].to_sym,
          filename_pattern: mod_data['filename_pattern'],
          depends_on: mod_data['depends_on'] || [],
          is_platform: mod_data['is_platform'] || false,
          optional: mod_data['optional'] || false
        )
      end
    rescue Psych::SyntaxError => e
      raise DeclarationError, "YAML syntax error in #{base_dir}: #{e.message}"
    end

    def validate_yaml_declaration!(mod_config)
      missing_fields = REQUIRED_FIELDS.reject { |field| mod_config[field] }
      
      if missing_fields.any?
        raise DeclarationError, "Missing required fields in mod config: #{missing_fields.join(', ')}"
      end

      unless %w[server_only client_and_server].include?(mod_config['type'])
        raise DeclarationError, "Invalid type '#{mod_config['type']}' for mod '#{mod_config['name']}'. Must be 'server_only' or 'client_and_server'."
      end
      
      true
    end
  end
end