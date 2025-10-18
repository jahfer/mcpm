require 'test_helper'
require 'mcpm/commands/outdated'

module MCPM
  module Commands
    class OutdatedTest < Minitest::Test
      NAME = "outdated".freeze
      MockOpts = Data.define(:dir)

      def setup
        @cmd = ::Outdated.new
      end

      def test_invoke
        with_mock_world do |mod_config|
          op = MockOpts.new(dir: mod_config.base_dir)
          @cmd.invoke(op, NAME)

          # mod_files = Dir.glob(File.join(working_dir, "mods", "*.jar"))
          # assert_equal(2, mod_files.size)
        end 
      end

      def test_check_mod_versions
        with_mock_world do |mod_config|
          result = @cmd.check_mod_versions(mod_config)
          assert_equal 4, result.keys.count
        end
      end
    end
  end
end
