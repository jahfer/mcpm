require 'test_helper'
require 'yaml'
require 'mods/mods'
require 'mods/updater'

class ModConfigCacheTest < Minitest::Test
  def test_install_mod_invalidates_the_cached_jar_list
    mod_declaration = mod_declaration_for('example-mod')

    with_config(mods: []) do |config|
      assert_equal [], config.jar_files

      installed_jar = File.join(config.mods_dir, 'example-mod-1.0.0.jar')
      fake_updater = Object.new
      fake_updater.define_singleton_method(:download_mod) do |_decl|
        FileUtils.touch(installed_jar)
      end
      Mods::Updater.stubs(:new).returns(fake_updater)

      config.install_mod!(mod_declaration)

      assert_equal [installed_jar], config.jar_files
      assert_equal 'example-mod-1.0.0.jar', config.find_installed_mod(mod_declaration).filename
    end
  end

  def test_update_mod_invalidates_the_cached_jar_list_after_removing_the_old_jar
    with_config(mods: [mod_hash('example-mod')]) do |config|
      old_jar = File.join(config.mods_dir, 'example-mod-1.0.0.jar')
      FileUtils.touch(old_jar)

      installed_mod = config.find_installed_mod(config.mod_declarations.first)
      assert_equal [old_jar], config.jar_files

      new_jar = File.join(config.mods_dir, 'example-mod-2.0.0.jar')
      fake_updater = Object.new
      fake_updater.define_singleton_method(:download_mod) do |_decl|
        FileUtils.touch(new_jar)
      end

      Mods::Updater.stubs(:new).returns(fake_updater)
      config.stubs(:can_update?).with(installed_mod).returns(true)

      config.update_mod!(installed_mod)

      assert_equal [new_jar], config.jar_files
      assert_equal 'example-mod-2.0.0.jar', config.find_installed_mod(installed_mod.declaration).filename
      refute File.exist?(old_jar)
    end
  end

  def test_apply_updates_invalidates_the_cached_jar_list_after_replacing_the_mods_directory
    with_config(mods: [mod_hash('example-mod')]) do |config|
      old_jar = File.join(config.mods_dir, 'example-mod-1.0.0.jar')
      FileUtils.touch(old_jar)

      assert_equal [old_jar], config.jar_files

      Dir.mktmpdir('mcpm-working') do |working_dir|
        expected_jar = File.join(config.mods_dir, 'example-mod-2.0.0.jar')
        FileUtils.touch(File.join(working_dir, 'example-mod-2.0.0.jar'))

        updater = Mods::Updater.new(config, working_dir, config.minecraft_version)
        updater.apply_updates!

        assert_equal [expected_jar], config.jar_files
      end
    end
  end

  private

  def with_config(mods:)
    Dir.mktmpdir('mcpm-cache') do |dir|
      FileUtils.mkdir_p(File.join(dir, 'mods'))
      File.write(
        File.join(dir, 'mcpm.yml'),
        YAML.dump(
          'loader' => 'fabric',
          'minecraft_version' => '1.21.1',
          'mods' => mods
        )
      )

      yield Mods::ModConfig.new(dir)
    end
  end

  def mod_declaration_for(name)
    Mods::ModDeclaration.new(
      project_id: name,
      name: name,
      type: :client_and_server,
      filename_pattern: "^#{Regexp.escape(name)}-.*\\.jar$",
      depends_on: [],
      is_platform: false,
      optional: false
    )
  end

  def mod_hash(name)
    {
      'project_id' => name,
      'name' => name,
      'type' => 'client_and_server',
      'filename_pattern' => "^#{Regexp.escape(name)}-.*\\.jar$"
    }
  end
end
