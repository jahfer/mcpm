require 'yaml'
require 'zip'
require 'json'
require 'mods/modrinth'
require 'mods/minecraft_version'

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
  end

  InstalledMod = Data.define(
    :declaration,
    :version,
    :filename,
    :filepath,
    :minecraft_version
  ) do
    def supported_minecraft_versions(mod_loader: nil)
      declaration.supported_minecraft_versions(mod_loader: mod_loader)
    end

    def maximum_supported_minecraft_version(mod_loader: nil)
      supported_minecraft_versions(mod_loader:).last
    end

    def platform? = declaration.platform?
    def optional? = declaration.optional?
    def required? = !optional?
  end

  VersionInfo = Data.define(
    :version,
    :minecraft_version
  )

  UNKNOWN_VERSION = VersionInfo.new(nil, nil)
  
  class ModConfig
    Error = Class.new(StandardError)
    DeclarationError = Class.new(Error)
    MissingModError = Class.new(Error)
    AmbiguousModError = Class.new(Error)
    REQUIRED_FIELDS = %w[project_id name type filename_pattern].freeze

    attr_reader :base_dir

    def initialize(base_dir)
      self.base_dir = base_dir
    end

    def minecraft_version
      version = config_data['minecraft_version']
      raise DeclarationError, "Missing 'minecraft_version' in mcpm.yml" unless version

      MinecraftVersion.new(version)
    end

    def mod_declarations
      @mod_declarations ||= load_mod_declarations
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

    def find_installed_mod(mod_declaration)
      pattern = Regexp.new(mod_declaration.filename_pattern, Regexp::IGNORECASE)
      matching_jars = jar_files.select { |jar| File.basename(jar) =~ pattern }

      if matching_jars.empty?
        raise MissingModError, "No installed JAR file matches pattern for mod: #{mod_declaration.name}"
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

    def mods_dir
      @mods_dir ||= File.join(base_dir, 'mods')
    end

    def jar_files
      @jar_files ||= Dir.glob(File.join(mods_dir, '*.jar'))
    end

    def mod_loader
      config_data['mod_loader'] || 'fabric'
    end

    private

    attr_writer :base_dir

    def config_data
      @config_data ||= begin
        yaml = File.join(base_dir, 'mcpm.yml')
        unless File.exist?(yaml)
          puts "No mcpm.yml found in #{base_dir}"
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
      rescue => e
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