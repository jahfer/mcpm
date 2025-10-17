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

      def test_invoke
        Dir.mktmpdir("mcpm-install_test-test_invoke") do |working_dir|
          FileUtils.copy_entry("test/fixtures/world/", working_dir)

          Mods::ModConfig.any_instance.expects(:install_mod!).times(19)

          op = MockOpts.new(dir: working_dir)
          @cmd.invoke(op, NAME)

          # mod_files = Dir.glob(File.join(working_dir, "mods", "*.jar"))
          # assert_equal(2, mod_files.size)
        end 
      end
    end
  end
end