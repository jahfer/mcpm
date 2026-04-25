require 'mcpm'

class Help < CLI::Kit::BaseCommand
  command_name('help')
  desc('Show help for a command, or this page')
  usage('')
  usage('[command]')
  example('', 'show all available commands')
  example('install', 'show help for the install command')

  class Opts < CLI::Kit::Opts
    def command
      position(desc: 'Command to show help for')
    end
  end

  def invoke(op, _name)
    command_name = op.command

    if command_name
      command, resolved_name = MCPM::Commands::Registry.lookup_command(command_name)
      raise CLI::Kit::Abort, "Unknown command '#{command_name}'" unless command

      puts command.build_help
      return
    end

    puts CLI::UI.fmt("{{bold:Available commands}}")
    puts

    MCPM::Commands::Registry.resolved_commands
      .sort_by(&:first)
      .each do |name, klass|
        next if name == 'help'

        desc = klass._desc
        line = "{{command:#{MCPM::TOOL_NAME} #{name}}}"
        line << " - #{desc}" if desc
        puts CLI::UI.fmt(line)
      end

    puts
    puts CLI::UI.fmt("Run {{command:#{MCPM::TOOL_NAME} help COMMAND}} or {{command:#{MCPM::TOOL_NAME} COMMAND --help}} for more details.")
  end
end
