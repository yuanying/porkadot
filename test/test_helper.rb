$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)

ROOT = File.expand_path("../..", __FILE__)
TEST_DIR = File.join(ROOT, 'test')
TEST_FIXTURES_DIR = File.join(TEST_DIR, 'fixtures')

require "porkadot"
require "tmpdir"
require "fileutils"
require "yaml"

module Porkadot::TestUtils
  # The defaults porkadot ships with. Renovate raises the versions in this
  # file, so tests read them from here rather than writing them again.
  def default_config
    YAML.load_file(File.join(ROOT, 'lib', 'porkadot', 'default.yaml'))
  end

  # The image on the line after a template's Renovate comment for dep_name,
  # which is the version Renovate raises for an image written in a template.
  def renovate_tracked_image(template, dep_name)
    path = File.join(ROOT, 'lib', 'porkadot', 'assets', template)
    comment = /<%-# renovate: datasource=\S+ depName=#{Regexp.escape(dep_name)}[ \S]* -%>\n\s*image: (\S+)/
    File.read(path)[comment, 1] or raise "no Renovate comment for #{dep_name} in #{template}"
  end

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

  # Renders certs and kubernetes once per process, since generating the
  # certificates is slow, and copies the result into dir. Returns the path
  # of a config whose assets_dir points into dir.
  def copy_rendered_kubernetes(dir)
    @@rendered_kubernetes ||= Dir.mktmpdir.tap do |src|
      path = write_tmp_config(src)
      run_cli('render', 'certs', '--config', path)
      run_cli('render', 'kubernetes', '--config', path)
      Minitest.after_run { FileUtils.remove_entry(src) }
    end
    FileUtils.cp_r(File.join(@@rendered_kubernetes, 'assets'), dir)
    write_tmp_config(dir)
  end

  def run_cli(*args)
    capture_io do
      Porkadot::Cmd::Cli.start(args)
    end
  end
end

require "minitest/autorun"
