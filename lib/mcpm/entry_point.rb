require 'mcpm'

module MCPM
  module EntryPoint
    ROOT_HELP_ARGS = %w[-h --help help].freeze

    def self.call(args)
      args = normalize_args(args)

      cmd, command_name, args = MCPM::Resolver.call(args)
      MCPM::Executor.call(cmd, command_name, args)
    end

    def self.normalize_args(args)
      return ['help'] if args.empty?
      return ['help', *args.drop(1)] if ROOT_HELP_ARGS.include?(args.first)

      args
    end
    private_class_method :normalize_args
  end
end
