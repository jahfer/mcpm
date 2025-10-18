require "mods/mods"
require "ori"

class Outdated < CLI::Kit::BaseCommand
  command_name('outdated')
  desc('Checks for outdated mods in the MCPM YAML configuration file.')
  long_desc(<<~LONGDESC)
    Checks for outdated mods in the MCPM YAML configuration file in the specified directory
    (or the current directory if none is specified).
  LONGDESC
  usage('')
  example('', "check for outdated mods in the MCPM YAML configuration file for the 'my-world' server")

  class Opts < CLI::Kit::Opts
    def dir
      path = option!(long: '--dir', short: '-d', desc: 'Directory containing the MCPM configuration file', default: Dir.pwd)
      File.expand_path(path)
    end
  end
  
  def invoke(op, _name)
    mod_config = mod_config(op.dir)
    mod_versions = {}
    
    CLI::UI::Frame.open("Checking for outdated mods") do
      CLI::UI::Spinner.spin("Checking...") do |spinner|
        mod_versions = check_mod_versions(mod_config)

        spinner.update_title("{{green:Version check complete.}}")
      end
    end

    CLI::UI::Frame.open("Summary") do
      outdated_mods = []
      mod_versions.each do |mod_decl, (latest_verison, installed_version)|
        unless latest_verison&.include?(installed_version)
          outdated_mods << mod_decl
        end
      end
      
      if outdated_mods.empty?
        puts CLI::UI.fmt("{{green:All mods are up to date.}}")
      else
        puts CLI::UI.fmt("{{yellow:Found #{outdated_mods.size} outdated mod(s):}}")
        outdated_mods.each do |mod_decl|
          latest_version, installed_version = mod_versions.fetch(mod_decl, ["not installed", "not installed"])
          puts CLI::UI.fmt("  * {{bold:#{mod_decl.name}}} ({{green:#{latest_version}}} > {{cyan:#{installed_version}}})")
        end
      end
    end
  end

  def check_mod_versions(mod_config)
    mod_versions = {}

    Ori.sync do |scope|
      scope.fork_each(mod_config.mod_declarations) do |mod_decl|
        latest_version = mod_config.next_available_version(mod_decl)

        installed_version = begin  
          mod_config.find_installed_mod(mod_decl).version
        rescue Mods::ModConfig::MissingModError
          "?"
        end

        mod_versions[mod_decl] = [latest_version, installed_version]
      end
    end
    
    mod_versions
  end

  private

  def mod_config(dir)
    Mods::ModConfig.new(dir)
  end
end
