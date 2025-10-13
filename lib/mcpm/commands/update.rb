require "mods/mods"

class Update < CLI::Kit::BaseCommand
  command_name('update')
  desc('Updates a specific mod to the latest compatible version.')
  long_desc(<<~LONGDESC)
    Updates the MCPM YAML configuration file in the specified directory
    (or the current directory if none is specified).
  LONGDESC
  usage('[mod_id]')
  example('P7dR8mSH', "update the mod with ID 'P7dR8mSH' (Fabric API) to the latest compatible version")

  class Opts < CLI::Kit::Opts
    def dir
      path = option!(long: '--dir', short: '-d', desc: 'Directory containing the MCPM configuration file', default: Dir.pwd)
      File.expand_path(path)
    end

    def mod_name
      position!
    end

    def dry_run
      flag(long: '--dry-run', short: '-D', desc: 'Show what would be updated without making any changes')
    end
  end
  
  def invoke(op, _name)
    config = mod_config(op.dir)

    CLI::UI::Frame.open("Updating '#{op.mod_name}'") do
      CLI::UI::Spinner.spin("Checking for updates") do |spinner|
        mod = config.find_installed_mod_by_id(op.mod_name) 
        mod ||= config.find_installed_mod_by_name(op.mod_name)

        raise "Mod '#{op.mod_name}' not found in configuration" unless mod

        if config.can_update?(mod)
          spinner.update_title("{{green:Mod '#{mod.declaration.name}' can be updated from {{bold:#{mod.version}}} to {{bold:#{config.next_available_version(mod.declaration)}}}.}}")
        else
          spinner.update_title("{{red:Mod '#{mod.declaration.name}' is already at the latest compatible version ({{bold:#{mod.version}}}).}}")
        end
      end

      return if op.dry_run

      config.update_mod!(mod)
      puts CLI::UI.fmt("{{green:Mod '#{mod.declaration.name}' updated successfully to version {{bold:#{config.find_installed_mod_by_id(mod.declaration.project_id).version}}}.}}")
    end
  end

  private

  def mod_config(dir)
    Mods::ModConfig.new(dir)
  end
end