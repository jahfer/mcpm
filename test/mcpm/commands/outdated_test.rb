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
        Dir.mktmpdir("mcpm-outdated_test-test_invoke") do |working_dir|
          FileUtils.copy_entry("test/fixtures/world/", working_dir)

          op = MockOpts.new(dir: working_dir)
          @cmd.invoke(op, NAME)

          # mod_files = Dir.glob(File.join(working_dir, "mods", "*.jar"))
          # assert_equal(2, mod_files.size)
        end 
      end
    end
  end
end