require "test_helper"
require "tmpdir"
require "fileutils"

class PorkadotRenderEtcdTest < Minitest::Test
  include Porkadot::TestUtils

  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = write_tmp_config(@tmpdir)
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  # The etcd client key must not be readable by other users on the node.
  # install(1) also resets the owner and mode of files that already exist.
  def test_install_script_installs_pki_as_root_only
    run_cli('render', 'certs', '--config', @config_path)
    run_cli('render', 'etcd', '--config', @config_path)

    script = File.read(File.join(@tmpdir, 'assets', 'kubelet', 'node01', 'addons', 'etcd', 'install.sh'))
    %w(ca.crt etcd.crt etcd.key).each do |file|
      assert_includes script, "install -m 0600 -o root -g root ${ROOT}/#{file} /etc/etcd/pki/#{file}"
    end
    refute_match %r{^cp .*/etcd\.(crt|key) }, script
  end
end
