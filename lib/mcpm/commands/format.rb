require "mods/mods"
require "utility/yaml"

class Format < CLI::Kit::BaseCommand
  command_name('fmt')
  desc('Formats the MCPM YAML configuration file.')
  long_desc(<<~LONGDESC)
    Formats the MCPM YAML configuration file in the specified directory
    (or the current directory if none is specified).
  LONGDESC
  usage('[dir]')
  example('my-world', "format the MCPM YAML configuration file for the 'my-world' server")

  class Opts < CLI::Kit::Opts
    def dir
      File.expand_path(position!)
    end
  end
  
  def invoke(op, _name)
    config = mod_config(op.dir)
    filepath = File.join(op.dir, Mods::ModConfig::YAML_CONFIG_FILE)
    puts "Formatting MCPM configuration in #{op.dir}"
    Utility::YAML.dump_to_file(config.to_h, filepath:)
    puts "Formatted configuration written to #{filepath}"
  end

  private

  def mod_config(dir)
    Mods::ModConfig.new(dir)
  end
end