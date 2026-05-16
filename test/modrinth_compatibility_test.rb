require 'test_helper'
require 'mods/mods'

module Mods
  class ModrinthCompatibilityTest < Minitest::Test
    def setup
      Modrinth.instance_variable_set(:@fetch_supported_versions, nil)
    end

    def test_fetch_available_versions_falls_back_to_compatible_year_based_hotfixes
      Modrinth.stubs(:fetch_versions_response)
        .with('project-id', minecraft_version: MinecraftVersion['26.1.2'], mod_loader: 'fabric')
        .returns([])

      Modrinth.stubs(:fetch_versions_response)
        .with('project-id', mod_loader: 'fabric')
        .returns([
          { 'version_number' => '2.0.0', 'game_versions' => ['26.1.1'] },
          { 'version_number' => '1.0.0', 'game_versions' => ['1.21.11'] },
        ])

      versions = Modrinth.fetch_available_versions('project-id', minecraft_version: MinecraftVersion['26.1.2'], mod_loader: 'fabric')

      assert_equal ['2.0.0'], versions.map(&:version)
      assert_equal ['26.1.1'], versions.map { |version| version.minecraft_version.to_s }
    end

    def test_remote_file_for_mod_uses_compatible_year_based_hotfixes_when_exact_version_is_missing
      Modrinth.stubs(:fetch_versions_response)
        .with('project-id', minecraft_version: MinecraftVersion['26.1.2'], mod_loader: 'fabric')
        .returns([])

      Modrinth.stubs(:fetch_versions_response)
        .with('project-id', mod_loader: 'fabric')
        .returns([
          { 'id' => 'version-123', 'version_number' => '2.0.0', 'game_versions' => ['26.1.1'] },
        ])

      Modrinth.stubs(:fetch_version_response)
        .with('version-123')
        .returns({ 'files' => [{ 'filename' => 'mod.jar', 'url' => 'https://example.test/mod.jar' }] })

      file = Modrinth.remote_file_for_mod(project_id: 'project-id', minecraft_version: MinecraftVersion['26.1.2'], mod_loader: 'fabric')

      assert_equal 'mod.jar', file.fetch('filename')
    end
  end
end
