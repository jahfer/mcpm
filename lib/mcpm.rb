require 'cli/ui'
require 'cli/kit'

CLI::UI::StdoutRouter.enable

module MCPM
  TOOL_NAME = 'mcpm'
  ROOT = File.expand_path('../..', __dir__)
  LOG_FILE  = '/tmp/mcpm.log'

  autoload :EntryPoint, 'mcpm/entry_point'
  autoload :Commands, 'mcpm/commands'

  Config = CLI::Kit::Config.new(tool_name: TOOL_NAME)
  Command = CLI::Kit::BaseCommand

  CLI::Kit::CommandHelp.tool_name=TOOL_NAME

  Executor = CLI::Kit::Executor.new(log_file: LOG_FILE)
  Resolver = CLI::Kit::Resolver.new(
    tool_name: TOOL_NAME,
    command_registry: MCPM::Commands::Registry
  )

  ErrorHandler = CLI::Kit::ErrorHandler.new(log_file: LOG_FILE)
end