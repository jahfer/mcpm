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
        with_mock_world do |mod_config|
          Mods::ModConfig.any_instance.expects(:install_mod!).times(3)

          op = MockOpts.new(dir: mod_config.base_dir)
          @cmd.invoke(op, NAME)

          # mod_files = Dir.glob(File.join(working_dir, "mods", "*.jar"))
          # assert_equal(2, mod_files.size)
        end 
      end
    end
  end
end
