$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)

ROOT = File.expand_path("../..", __FILE__)
TEST_DIR = File.join(ROOT, 'test')
TEST_FIXTURES_DIR = File.join(TEST_DIR, 'fixtures')

require "porkadot"

module Porkadot::TestUtils
  def mock_config(file='porkadot.yaml')
    Porkadot::Config.new(File.join(TEST_FIXTURES_DIR, 'config', file))
  end
end

require "minitest/autorun"
