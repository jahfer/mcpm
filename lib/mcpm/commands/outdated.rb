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
    outdated_mods = []
    mod_versions = {}
    
    CLI::UI::Frame.open("Checking for outdated mods") do
      CLI::UI::Progress.progress do |bar|
        mod_config.mod_declarations.each_with_index do |mod_decl, index|
          bar.tick(set_percent: (index + 1).to_f / mod_config.mod_declarations.length)

          latest_version = mod_config.next_available_version(mod_decl)

          installed_version = begin  
            installed_mod = mod_config.find_installed_mod(mod_decl)
          rescue Mods::ModConfig::MissingModError
            "?"
          end

          if latest_version && latest_version != installed_version
            mod_versions[mod_decl.name] = [latest_version, installed_version]
            outdated_mods << mod_decl
          end
        end
      end

      if outdated_mods.empty?
        puts CLI::UI.fmt("\n{{green:All mods are up to date.}}")
        return
      else
        puts CLI::UI.fmt("\n{{yellow:Found #{outdated_mods.size} outdated mod(s):}}")
        outdated_mods.each do |mod_decl|
          latest_version, installed_version = mod_versions.fetch(mod_decl.name, ["not installed", "not installed"])
          puts CLI::UI.fmt("  * {{bold:#{mod_decl.name}}} ({{green:#{latest_version}}} > {{cyan:#{installed_version}}})")
        end
      end

    end
  end

  private

  def mod_config(dir)
    Mods::ModConfig.new(dir)
  end
end