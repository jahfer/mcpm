require "mods/mods"
require "mods/updater"

class Upgrade < CLI::Kit::BaseCommand
  command_name('upgrade')
  desc('Check whether an upgrade is possible for the specified Minecraft server')
  long_desc(<<~LONGDESC)
    Check whether an upgrade is possible for the specified Minecraft server.
    If no server is specified, the command will check the current server in the working directory.
  LONGDESC
  usage('[dir]')
  example('my-world', "check whether an upgrade is possible for the 'my-world' server")

  class Opts < CLI::Kit::Opts
    def dir
      File.expand_path(position!)
    end

    def dry_run
      flag(short: '-d', long: '--dry-run', desc: 'Run the command without making any changes')
    end

    def ignore_optional
      flag(short: '-i', long: '--ignore-optional', desc: 'Ignore optional mods when determining upgrade compatibility')
    end

    def force
      flag(short: '-f', long: '--force', desc: 'Force the upgrade even if not all mods support the target Minecraft version')
    end
  end
  
  def invoke(op, _name)
    config = nil
    installed_mods = nil
    missing_mods = nil

    CLI::UI::Frame.open("Mod Discovery") do
      puts CLI::UI.fmt("{{blue:🔍}} Loading mod configuration and discovering installed mods...")
      config = mod_config(op.dir)
      mod_declarations = load_mod_declarations(config)
      puts CLI::UI.fmt("{{green:✓}} Loaded configuration for {{bold:#{mod_declarations.length}}} mod(s)")
      load_mod_installations(config) => { installed_mods:, missing_mods:, undeclared_mods: }

      if undeclared_mods.any?
        puts CLI::UI.fmt("\n{{yellow:⚠ Unmanaged JAR files found in mods directory:}}")
        undeclared_mods.each do |jar|
          puts CLI::UI.fmt("  {{yellow:•}} #{File.basename(jar)}")
        end
        puts CLI::UI.fmt("{{yellow:💡 These files do not match any configured mod patterns.}}")
      end
    rescue Mods::ModConfig::DeclarationError => e
      puts CLI::UI.fmt("{{red:Error loading mod configuration: #{e.message}")
      exit 1
    rescue => e
      puts CLI::UI.fmt("{{red:✗}} Error loading mods configuration: #{e.message}")
      exit 1
    end

    latest_common_version = nil
    required_supported_minecraft_versions = []

    CLI::UI::Frame.open("Maximum Minecraft Version Analysis") do
      puts CLI::UI.fmt("{{blue:🔍}} Analyzing maximum Minecraft version support across all mods...")

      if installed_mods.empty?
        puts CLI::UI.fmt("{{yellow:⚠}} No mods found, cannot determine maximum Minecraft version")
        exit 1
      end

      supported_minecraft_versions = []
      max_minecraft_version_seen = nil
      CLI::UI::Progress.progress do |bar|
        supported_minecraft_versions = installed_mods.map.with_index do |mod, index|
          bar.tick(set_percent: (index + 1).to_f / installed_mods.length)
          
          latest_supported_version = mod.maximum_supported_minecraft_version(mod_loader: config.mod_loader)
          max_minecraft_version_seen = latest_supported_version if max_minecraft_version_seen.nil? || (latest_supported_version && (max_minecraft_version_seen < latest_supported_version))
          
          supported_versions = mod.supported_minecraft_versions(mod_loader: config.mod_loader)

          if op.ignore_optional && mod.required?
            required_supported_minecraft_versions << supported_versions
          end

          supported_versions
        end
      end

      common_versions = supported_minecraft_versions.reduce(:&)
      if common_versions.nil? || common_versions.empty?
        puts CLI::UI.fmt("{{red:✗}} No common Minecraft version found across all managed mods.")
        return
      end

      latest_common_version = common_versions.sort.last
      puts CLI::UI.fmt("\n{{blue:ℹ}} Highest release version any mod supports: {{bold:#{latest_common_version}}}")

      installed_mods
        .group_by { |mod| mod.maximum_supported_minecraft_version(mod_loader: config.mod_loader) }
        .each_pair
        .sort_by(&:first)
        .each do |version, mods|
          version_color = if version == max_minecraft_version_seen
            "green"
          else
            "yellow"
          end

          puts CLI::UI.fmt("\n{{#{version_color}:📌 Minecraft #{version}:}} (#{mods.length} mod#{'s' if mods.length != 1})")
          mods.sort_by { |mod| -config.dependents_of(mod).length }.each do |mod|
            type_label = mod.declaration.type == :server_only ? 'Server-Only' : 'Client+Server'
            type_color = mod.declaration.type == :server_only ? 'green' : 'blue'
            platform_indicator = mod.platform? ? ' {{yellow:[PLATFORM]}}' : ''

            dependents_count = config.dependents_of(mod).length
            dependents_info =  dependents_count > 0 ? " {{gray:(#{dependents_count} dependent#{'s' if dependents_count != 1})}}" : ''
            optional_indicator = mod.optional? ? ' {{gray:[OPTIONAL]}}' : ''

            puts CLI::UI.fmt("  {{gray:•}} {{cyan:#{mod.declaration.name}}} ({{#{type_color}:#{type_label}}})#{platform_indicator}#{dependents_info}#{optional_indicator}")
          end
      end
    end

    upgradeable_minecraft_version = latest_common_version
    CLI::UI::Frame.open("Upgrade Minecraft") do
      if latest_common_version > config.minecraft_version
        puts CLI::UI.fmt("\n{{green:🎉 An upgrade is available to Minecraft version #{latest_common_version}!}}")
      elsif op.ignore_optional
        required_common_version = required_supported_minecraft_versions.reduce(:&).sort.last
        if required_common_version && required_common_version > config.minecraft_version
          upgradeable_minecraft_version = required_common_version
          puts CLI::UI.fmt("{{green:🚀 Ignoring optional mods, the server can be upgraded to {{bold:#{required_common_version}}}!}}")
        elsif op.force
          puts CLI::UI.fmt("{{yellow:⚠ Forcing upgrade despite not all required mods supporting a Minecraft version newer than {{bold:#{config.minecraft_version}}}.}}")
        else
          puts CLI::UI.fmt("{{yellow:ℹ No upgrade available, not all required mods support a Minecraft version newer than {{bold:#{config.minecraft_version}}}.}}")
          return
        end
      else
        puts CLI::UI.fmt("{{yellow:ℹ No upgrade available, not all mods support a Minecraft version newer than {{bold:#{config.minecraft_version}}}.}}")
        puts CLI::UI.fmt("{{yellow:  Use {{bold:--ignore-optional}} to check again, ignoring optional mods.}}")
        return
      end

      if op.dry_run
        puts CLI::UI.fmt("{{blue:🔍}} Remove {{bold:--dry-run}} to perform the upgrade.")
        return
      end

      CLI::UI.puts("{{yellow:⚠ Please ensure the server is stopped before applying updates.}}\n")
      answer = CLI::UI.ask("Proceed to download mods and apply the updates?", options: %w(yes no), default: 'yes')
      return unless answer == 'yes'

      Mods::Updater.attempt_update(config, to_minecraft_version: upgradeable_minecraft_version) do |updater|
        puts CLI::UI.fmt("{{blue:🔧}} Upgrading server to Minecraft version {{bold:#{upgradeable_minecraft_version}}}...")

        mods_to_update = installed_mods.map(&:declaration) + missing_mods

        state = {
          successful: [],
          failed: [],
          processing: [],
          waiting: mods_to_update.dup
        }

        spinner_title = ->() { " Downloading updated mods: {{@widget/status:#{state[:successful].length}:#{state[:failed].length}:#{state[:processing].length}:#{state[:waiting].length}}}" }

        CLI::UI::Frame.open("Mod Downloads") do
          CLI::UI::Spinner.spin(spinner_title.call) do |spinner|
            mods_to_update.each_with_index do |mod, index|
              state[:waiting].delete(mod)
              state[:processing] << mod
              spinner.update_title(spinner_title.call)

              success = false
              
              begin
                updater.update_mod(mod)
                success = true
              rescue Mods::Modrinth::NotFoundError => e
                puts CLI::UI.fmt("{{yellow:⚠}} Could not find an updated version for mod {{cyan:#{mod.name}}}: #{e.message}")
              rescue Mods::Modrinth::APIError => e
                puts CLI::UI.fmt("{{red:✗}} Error while checking for updates for mod {{cyan:#{mod.name}}}: #{e.message}")
              rescue => e
                puts CLI::UI.fmt("{{red:✗ Unexpected error while updating {{cyan:#{mod.name}}}: #{e.message}}}")
              ensure
                state[:processing].delete(mod)

                if success
                  state[:successful] << mod
                else
                  state[:failed] << mod
                end

                spinner.update_title(spinner_title.call)
                updater.fail! unless success
              end
            end

            spinner.update_title(" All mods downloaded successfully")
          end

          if updater.failed?
            puts CLI::UI.fmt("{{red:✗}} The following mods failed to upgrade, no changes have been made.")

            state[:failed].each do |mod|
              puts CLI::UI.fmt("  {{red:•}} {{cyan:#{mod.name}}}")
            end

            exit 1 
          end
        end

        CLI::UI::Frame.open("Applying Mod Updates") do
          updater.backup_existing_mods
          puts CLI::UI.fmt("{{v}} Mods backed up to {{cyan:#{updater.backup_filepath}}}")
          updater.apply_updates!
          puts CLI::UI.fmt("{{v}} Upgrade to Minecraft version {{bold:#{upgradeable_minecraft_version}}} completed successfully!")
        rescue => error
          puts CLI::UI.fmt("{{x}} Failed to apply updates: #{error.message}")
          choice = CLI::UI.ask('Retry?', options: %w(yes no), default: 'no')
          if choice == 'yes'
            begin
              updater.apply_updates!
            rescue => error
              puts CLI::UI.fmt("{{x}} Failed again to apply updates: #{error.message}")
            end
          end
        end
      end
    end
  end

  private

  def mod_config(dir)
    Mods::ModConfig.new(dir)
  end

  def load_mod_declarations(mod_config)
    declarations = mod_config.mod_declarations

    if declarations.empty?
      puts "No mods defined in mcpm.yml"
      exit 1
    end

    declarations
  end

  def load_mod_installations(mod_config)
    puts CLI::UI.fmt("{{blue:📁}} Found {{bold:#{mod_config.jar_files.length}}} JAR file(s) in mods directory")

    installed_mods = []
    missing_mods = []
    undeclared_mods = mod_config.jar_files.dup

    processing_messages = []

    CLI::UI::Progress.progress do |bar|
      mod_config.mod_declarations.each_with_index do |mod_decl, index|
        bar.tick(set_percent: (index + 1).to_f / mod_config.mod_declarations.length)

        begin
          installed_mod = mod_config.find_installed_mod(mod_decl)
          
          installed_mods << installed_mod
          undeclared_mods.delete(installed_mod.filepath)
          processing_messages << { type: :success, message: "{{cyan:#{mod_decl.name}}} [{{cyan:#{mod_decl.type.to_s.gsub('_', '-')}}}] - v#{installed_mod.version || 'unknown'}" }
        rescue Mods::ModConfig::MissingModError => e
          missing_mods << mod_decl
          processing_messages << { type: :warning, message: e.message }
        rescue Mods::ModConfig::AmbiguousModError => e
          processing_messages << { type: :warning, message: e.message }
        end
      end
    end

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

    { installed_mods:, missing_mods:, undeclared_mods: }
  end
end