require 'tmpdir'
require 'mods/downloader'

module Mods
  class Updater
    Error = Class.new(StandardError)
    UpgradeError = Class.new(Error)

    class << self
      def attempt_update(config, to_minecraft_version:)
        Dir.mktmpdir("mcpm-upgrade-") do |working_dir|
          yield self.new(config, working_dir, to_minecraft_version)
        end
      rescue Mods::Updater::Error
      end
    end

    attr_reader :backup_filepath

    def initialize(config, working_dir, to_minecraft_version)
      self.config = config
      self.working_dir = working_dir
      self.to_minecraft_version = to_minecraft_version
      self.failed = false
      self.backed_up = false
      self.backup_filepath = nil
    end

    def update_mod(mod_declaration)
      file = Modrinth.remote_file_for_mod(
        project_id: mod_declaration.project_id,
        minecraft_version: to_minecraft_version,
        mod_loader: config.mod_loader
      )

      file_hash = file.fetch("hashes", {}).fetch("sha512", nil)
      raise UpgradeError, "No SHA512 hash available for mod #{mod_declaration.name}" unless file_hash

      filename = file.fetch("filename")
      download_url = file.fetch("url")
      destination_path = File.join(working_dir, filename)

      begin
        Downloader.download_file(download_url, destination_path)
        Downloader.verify_checksum(destination_path, file_hash)
      rescue Downloader::Error => e
        raise UpgradeError, "Update failed for mod #{mod_declaration.name}: #{e.message}"
      end
    end

    def apply_updates!(force: false)
      raise UpgradeError, "Cannot apply updates after a failed update" if failed? && !force

      backup_existing_mods unless backed_up?

      FileUtils.cp_r(working_dir, config.mods_dir, remove_destination: true)
    end

    def backup_existing_mods
      self.backup_filepath = File.join(config.base_dir, "mcpm_backup", "mcpm_backup_#{Time.now.strftime('%Y%m%d%H%M%S')}")
      FileUtils.mkdir_p(File.dirname(backup_filepath))
      FileUtils.cp_r(config.mods_dir, backup_filepath)

      self.backed_up = true
    end

    def fail!
      self.failed = true
      raise UpgradeError, "Upgrade failed, changes not persisted"
    end

    def failed? = failed
    def backed_up? = backed_up

    private

    attr_accessor :failed, :config, :working_dir, :to_minecraft_version, :backed_up
    attr_writer :backup_filepath
  end
end