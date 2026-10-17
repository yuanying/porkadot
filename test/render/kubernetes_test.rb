require "test_helper"
require "tmpdir"
require "fileutils"
require "yaml"

class PorkadotRenderKubernetesTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, 'porkadot.yaml')
    config = YAML.load_file(File.join(TEST_FIXTURES_DIR, 'config', 'porkadot.yaml'))
    config['local'] = { 'assets_dir' => File.join(@tmpdir, 'assets') }
    File.write(@config_path, YAML.dump(config))
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def test_install_script_prunes_allowlisted_kinds
    render('certs')
    render('kubernetes')

    allowlist = prune_allowlist
    assert_includes allowlist, 'apps/v1/deployment'
    assert_includes allowlist, 'core/v1/configmap'
  end

  # Pruning a Namespace deletes everything in it, and Namespaces such as
  # kube-system can be shared between addons, so they must never be pruned.
  def test_install_script_does_not_prune_namespaces
    render('certs')
    render('kubernetes')

    refute prune_allowlist.any? { |a| a.end_with?('/namespace') },
      "install.sh must not prune Namespaces: #{prune_allowlist.inspect}"
  end

  private

  def render(target)
    capture_io do
      Porkadot::Cmd::Cli.start(['render', target, '--config', @config_path])
    end
  end

  def prune_allowlist
    script = File.read(File.join(@tmpdir, 'assets', 'kubernetes', 'install.sh'))
    script.scan(/--prune-allowlist=(\S+?)"/).flatten
  end
end
