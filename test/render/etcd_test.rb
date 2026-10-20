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

  # etcd 3.6 renamed the --experimental-* flags and 3.7 removes the old
  # names, while 3.5 does not know the new ones.
  def test_etcd_36_uses_flags_renamed_from_experimental
    command = etcd_command

    assert_includes command, '--feature-gates=InitialCorruptCheck=true'
    assert_includes command, '--watch-progress-notify-interval=5s'
    assert_empty command.grep(/^--experimental-/)
  end

  def test_etcd_35_keeps_experimental_flags
    command = etcd_command(image_tag: '3.5.34-0')

    assert_includes command, '--experimental-initial-corrupt-check=true'
    assert_includes command, '--experimental-watch-progress-notify-interval=5s'
    assert_empty command.grep(/^--feature-gates=/)
    assert_empty command.grep(/^--watch-progress-notify-interval=/)
  end

  def test_etcd_newer_minor_uses_renamed_flags
    command = etcd_command(image_tag: '3.7.2-0')

    assert_includes command, '--feature-gates=InitialCorruptCheck=true'
    assert_empty command.grep(/^--experimental-/)
  end

  def test_etcd_manifest_uses_image_tag
    pod = etcd_manifest(image_tag: '3.5.34-0')

    assert_equal 'registry.k8s.io/etcd:3.5.34-0', pod['spec']['containers'].first['image']
  end

  private

  def etcd_manifest image_tag: nil
    config_path = @config_path
    if image_tag
      config = YAML.load_file(@config_path)
      config['etcd'] = { 'image_tag' => image_tag }
      File.write(config_path, YAML.dump(config))
    end
    run_cli('render', 'certs', '--config', config_path)
    run_cli('render', 'etcd', '--config', config_path)
    YAML.load_file(File.join(@tmpdir, 'assets', 'kubelet', 'node01', 'addons', 'etcd', 'etcd-server.yaml'))
  end

  def etcd_command image_tag: nil
    etcd_manifest(image_tag: image_tag)['spec']['containers'].first['command']
  end
end
