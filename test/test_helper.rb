$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)

ROOT = File.expand_path("../..", __FILE__)
TEST_DIR = File.join(ROOT, 'test')
TEST_FIXTURES_DIR = File.join(TEST_DIR, 'fixtures')

require "porkadot"
require "tmpdir"
require "fileutils"
require "yaml"

module Porkadot::TestUtils
  def mock_config(file='porkadot.yaml')
    Porkadot::Config.new(File.join(TEST_FIXTURES_DIR, 'config', file))
  end

  # Writes a copy of the fixture config whose assets_dir points into dir.
  # Extra settings under `local` (e.g. sops) can be given as local_overrides.
  def write_tmp_config(dir, file: 'porkadot.yaml', local_overrides: {})
    config = YAML.load_file(File.join(TEST_FIXTURES_DIR, 'config', file))
    config['local'] = { 'assets_dir' => File.join(dir, 'assets') }.merge(local_overrides)
    path = File.join(dir, 'porkadot.yaml')
    File.write(path, YAML.dump(config))
    path
  end

  def run_cli(*args)
    capture_io do
      Porkadot::Cmd::Cli.start(args)
    end
  end
end

require "minitest/autorun"
