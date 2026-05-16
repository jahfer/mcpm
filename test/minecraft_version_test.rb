require 'test_helper'
require 'mods/minecraft_version'

class MinecraftVersionTest < Minitest::Test
  def test_compatible_version_handles_patchfix_versions_in_both_directions
    assert_equal MinecraftVersion['1.21.10'], MinecraftVersion.compatible_version(MinecraftVersion['1.21.9'])
    assert_equal MinecraftVersion['1.21.9'], MinecraftVersion.compatible_version(MinecraftVersion['1.21.10'])
  end

  def test_year_based_versions_sort_after_legacy_versions
    assert MinecraftVersion['26.1'] > MinecraftVersion['1.21.11']
    assert MinecraftVersion['26.1.2'] > MinecraftVersion['26.1.1']
  end

  def test_year_based_hotfixes_share_a_compatibility_family
    assert MinecraftVersion['26.1'].compatible_with?(MinecraftVersion['26.1.2'])
    assert MinecraftVersion['26.1.1'].compatible_with?(MinecraftVersion['26.1.2'])
    refute MinecraftVersion['26.1.2'].compatible_with?(MinecraftVersion['26.2'])
  end

  def test_latest_version_supported_prefers_highest_hotfix_within_a_common_year_based_drop
    mod_supporting_26_1_1 = [
      MinecraftVersion['1.21.11'],
      MinecraftVersion['26.1.1'],
    ]

    mod_supporting_26_1_2 = [
      MinecraftVersion['1.21.11'],
      MinecraftVersion['26.1.2'],
    ]

    assert_equal(
      MinecraftVersion['26.1.2'],
      MinecraftVersion.latest_version_supported(mod_supporting_26_1_1, mod_supporting_26_1_2)
    )
  end

  def test_latest_version_supported_uses_normalized_versions_when_intersecting_patchfixes
    mod_supporting_patchfix = [
      MinecraftVersion['1.21.8'],
      MinecraftVersion['1.21.9'],
    ]

    mod_supporting_followup_release = [
      MinecraftVersion['1.21.8'],
      MinecraftVersion['1.21.10'],
    ]

    assert_equal(
      MinecraftVersion['1.21.10'],
      MinecraftVersion.latest_version_supported(mod_supporting_patchfix, mod_supporting_followup_release)
    )
  end

  def test_latest_version_supported_returns_nil_when_no_common_version_exists
    assert_nil MinecraftVersion.latest_version_supported(
      [MinecraftVersion['1.21.8']],
      [MinecraftVersion['26.2']]
    )
  end
end
