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

# Enable StdoutRouter — required by CLI::UI::Spinner and CLI::UI::Frame
# used in the command implementations under test.
CLI::UI::StdoutRouter.enable

require 'minitest/autorun'
MiniTest = Minitest unless defined?(MiniTest)
require 'mocha/minitest'

require 'mods/modrinth'

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def with_mock_world
  Dir.mktmpdir("mcpm-test") do |working_dir|
    FileUtils.copy_entry("test/fixtures/world/", working_dir)
    mod_config = Mods::ModConfig.new(working_dir)
    yield mod_config
  end
end

# Block all outbound HTTP in tests by default.
# Individual tests can stub Modrinth methods to return canned data instead.
module NetHTTPGuard
  def request(req, body = nil, &block)
    raise "Unexpected HTTP request in tests: #{req.method} #{req.uri || req.path}. " \
          "Stub the Modrinth (or Downloader) call instead."
  end
end

Net::HTTP.prepend(NetHTTPGuard)
