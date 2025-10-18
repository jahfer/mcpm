require 'test_helper'
require 'mcpm/commands/upgrade'

module MCPM
  module Commands
    class UpgradeTest < Minitest::Test
      NAME = "upgrade".freeze

      def test_invoke
        with_mock_world do |mod_config|
          op = stub(dir: mod_config.base_dir, ignore_optional: false, dry_run: true, force: false)
          upgrade = ::Upgrade.new
          upgrade.invoke(op, NAME)
        end 
      end
    end
  end
end
