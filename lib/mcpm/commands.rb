require 'mcpm'

module MCPM
  module Commands
    Registry = CLI::Kit::CommandRegistry.new(default: 'help')

    def self.register(const, cmd, path)
      autoload(const, path)
      Registry.add(->() { const_get(const) }, cmd)
    end

    register :Help, 'help', 'mcpm/commands/help'
    register :Upgrade, 'upgrade', 'mcpm/commands/upgrade'
    register :Format, 'fmt', 'mcpm/commands/format'
    register :Add, 'add', 'mcpm/commands/add'
    register :Update, 'update', 'mcpm/commands/update'
    register :Install, 'install', 'mcpm/commands/install'
    register :Outdated, 'outdated', 'mcpm/commands/outdated'
  end
end