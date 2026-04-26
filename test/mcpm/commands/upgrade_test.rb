require 'test_helper'
require 'mcpm/commands/upgrade'

module MCPM
  module Commands
    class UpgradeTest < Minitest::Test
      NAME = "upgrade".freeze

      def setup
        Mods::Modrinth.instance_variable_set(:@fetch_supported_versions, nil)
      end

      def test_invoke
        with_mock_world do |mod_config|
          # Stub Modrinth so no real HTTP calls are made.
          # Return a version higher than the fixture's 1.21.8 so the upgrade path triggers.
          Mods::Modrinth.stubs(:fetch_supported_versions).returns(
            [MinecraftVersion.new("1.21.8"), MinecraftVersion.new("1.21.9")]
          )
          Mods::Modrinth.stubs(:fetch_available_versions).returns(
            [Mods::VersionInfo.new("2.0.0", MinecraftVersion.new("1.21.9"))]
          )

          op = stub(
            dir: mod_config.base_dir,
            ignore_optional: false,
            dry_run: true,
            force: false
          )
          upgrade = ::Upgrade.new
          upgrade.invoke(op, NAME)
        end
      end
    end
  end
end
