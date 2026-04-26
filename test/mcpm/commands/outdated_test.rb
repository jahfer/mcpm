require 'test_helper'
require 'mcpm/commands/outdated'

module MCPM
  module Commands
    class OutdatedTest < Minitest::Test
      NAME = "outdated".freeze
      MockOpts = Data.define(:dir)

      def setup
        @cmd = ::Outdated.new
        # Clear any cached Modrinth responses between tests
        Mods::Modrinth.instance_variable_set(:@fetch_supported_versions, nil)
      end

      def test_check_mod_versions
        with_mock_world do |mod_config|
          # Stub every Modrinth call so no HTTP requests are made.
          # fetch_supported_versions is called inside ModDeclaration#supported_minecraft_versions
          Mods::Modrinth.stubs(:fetch_supported_versions).returns(
            [MinecraftVersion.new("1.21.8")]
          )
          Mods::Modrinth.stubs(:fetch_available_versions).returns(
            [Mods::VersionInfo.new("1.0.0", MinecraftVersion.new("1.21.8"))]
          )

          result = @cmd.check_mod_versions(mod_config)
          assert_equal 4, result.keys.count
        end
      end

      def test_invoke
        with_mock_world do |mod_config|
          Mods::Modrinth.stubs(:fetch_supported_versions).returns(
            [MinecraftVersion.new("1.21.8")]
          )
          Mods::Modrinth.stubs(:fetch_available_versions).returns(
            [Mods::VersionInfo.new("1.0.0", MinecraftVersion.new("1.21.8"))]
          )

          op = MockOpts.new(dir: mod_config.base_dir)
          @cmd.invoke(op, NAME)
        end
      end
    end
  end
end
