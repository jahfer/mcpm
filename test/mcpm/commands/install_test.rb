require 'test_helper'
require 'mcpm/commands/install'

module MCPM
  module Commands
    class InstallTest < Minitest::Test
      NAME = "install".freeze
      MockOpts = Data.define(:dir)

      def setup
        @cmd = ::Install.new
      end

      def test_invoke_installs_missing_mods
        with_mock_world do |mod_config|
          # There are 4 declared mods in the fixture and none are installed,
          # so install_mod! should be called once per mod.
          Mods::ModConfig.any_instance.stubs(:install_mod!)

          op = MockOpts.new(dir: mod_config.base_dir)
          @cmd.invoke(op, NAME)
        end
      end
    end
  end
end
