begin
  addpath = lambda do |p|
    path = File.expand_path("../../#{p}", __FILE__)
    $LOAD_PATH.unshift(path) unless $LOAD_PATH.include?(path)
  end
  addpath.call("lib")
end

require 'cli/kit'

require 'fileutils'
require 'tmpdir'
require 'tempfile'

require 'rubygems'
require 'bundler/setup'

require 'debug'

CLI::UI::StdoutRouter.enable

require 'minitest/autorun'
require "minitest/unit"
require 'mocha/minitest'

def with_mock_world
  Dir.mktmpdir("mcpm-test") do |working_dir|
    FileUtils.copy_entry("test/fixtures/world/", working_dir)
    mod_config = Mods::ModConfig.new(working_dir)
    yield mod_config
  end
end
