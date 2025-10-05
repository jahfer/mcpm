require 'mcpm'

module MCPM
  module Commands
    Registry = CLI::Kit::CommandRegistry.new(default: 'help')

    def self.register(const, cmd, path)
      autoload(const, path)
      Registry.add(->() { const_get(const) }, cmd)
    end

    register :Upgrade, 'upgrade', 'mcpm/commands/upgrade'
  end
end