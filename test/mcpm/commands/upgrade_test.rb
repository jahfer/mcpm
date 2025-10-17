require 'test_helper'
require 'mcpm/commands/upgrade'

module MCPM
  module Commands
    class UpgradeTest < Minitest::Test
      NAME = "upgrade".freeze

      def test_invoke
        Dir.mktmpdir("upgrade-test-test_invoke") do |working_dir|
          FileUtils.copy_entry("test/fixtures/world/", working_dir)
          
          op = stub(dir: working_dir, ignore_optional: false, dry_run: true, force: false)
          upgrade = ::Upgrade.new
          upgrade.invoke(op, NAME)
        end 
      end
    end
  end
end