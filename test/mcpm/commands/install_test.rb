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
          # Track which mods install_mod! is called with.
          # We can't use mocha expects/times here because Ori.sync
          # runs the calls concurrently and mocha isn't thread-safe.
          installed = Queue.new

          Mods::ModConfig.any_instance.stubs(:install_mod!).with do |mod_decl|
            installed << mod_decl.project_id
            true
          end

          op = MockOpts.new(dir: mod_config.base_dir)
          @cmd.invoke(op, NAME)

          installed_ids = []
          installed_ids << installed.pop until installed.empty?

          expected_ids = mod_config.mod_declarations.map(&:project_id)
          assert_equal expected_ids.sort, installed_ids.sort,
            "Expected install_mod! to be called for every declared mod"
        end
      end
    end
  end
end
