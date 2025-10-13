require "mods/mods"

class Install < CLI::Kit::BaseCommand
  command_name('install')
  desc('Installs a mod from the MCPM YAML configuration file.')
  long_desc(<<~LONGDESC)
    Installs a mod from the MCPM YAML configuration file in the specified directory
    (or the current directory if none is specified).
  LONGDESC
  usage('')
  example('', "install the MCPM YAML configuration file for the 'my-world' server")

  class Opts < CLI::Kit::Opts
    def dir
      path = option!(long: '--dir', short: '-d', desc: 'Directory containing the MCPM configuration file', default: Dir.pwd)
      File.expand_path(path)
    end
  end
  
  def invoke(op, _name)
    mod_config = mod_config(op.dir)
    missing_mods = []
    
    CLI::UI::Frame.open("Checking mods") do
      CLI::UI::Progress.progress do |bar|
        mod_config.mod_declarations.each_with_index do |mod_decl, index|
          bar.tick(set_percent: (index + 1).to_f / mod_config.mod_declarations.length)

          begin
            mod_config.find_installed_mod(mod_decl)
          rescue Mods::ModConfig::MissingModError
            missing_mods << mod_decl
          end
        end
      end

      if missing_mods.empty?
        puts CLI::UI.fmt("{{green:All mods are already installed.}}")
        return
      else
        puts CLI::UI.fmt("\n{{yellow:Found #{missing_mods.size} missing mod(s) to install.}}")
      end

    end

    CLI::UI::Frame.open("Installing #{missing_mods.size} mod(s)") do
      missing_mods.each_with_index do |mod_decl, index|
        CLI::UI::Spinner.spin("Installing '#{mod_decl.name}' (#{index + 1}/#{missing_mods.size})") do |spinner|
          begin
            mod_config.install_mod!(mod_decl)
            spinner.update_title("{{green:Installed '#{mod_decl.name}' successfully.}}")
          rescue StandardError => e
            spinner.update_title("{{red:Failed to install '#{mod_decl.name}': #{e.message}}}")
          end
        end
      end
    end
  end

  private

  def mod_config(dir)
    Mods::ModConfig.new(dir)
  end
end