require 'mcpm'

module MCPM
  module EntryPoint
    def self.call(args)
      cmd, command_name, args = MCPM::Resolver.call(args)
      MCPM::Executor.call(cmd, command_name, args)
    end
  end
end