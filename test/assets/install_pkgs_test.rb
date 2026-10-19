require "test_helper"
require "tmpdir"
require "fileutils"
require "open3"

class PorkadotAssetsInstallPkgsTest < Minitest::Test
  include Porkadot::TestUtils

  INITIATOR_NAME = "InitiatorName=iqn.2020-04.cloud.unstable:node01\n"
  # Written by the open-iscsi postinst on a fresh install.
  PACKAGE_INITIATOR_NAME = "InitiatorName=iqn.2004-10.com.ubuntu:01:0123456789ab\n"

  def setup
    @tmpdir = Dir.mktmpdir
    @etc_dir = File.join(@tmpdir, 'etc')
    @bin_dir = File.join(@tmpdir, 'bin')
    @log = File.join(@tmpdir, 'stub.log')
    FileUtils.mkdir_p(@bin_dir)
    FileUtils.mkdir_p(File.join(@etc_dir, 'iscsi'))
    FileUtils.mkdir_p(File.join(@etc_dir, 'modules-load.d'))
    FileUtils.mkdir_p(File.join(@etc_dir, 'sysctl.d'))
    write_stubs
    render_script
    File.write(File.join(@script_dir, 'initiatorname.iscsi'), INITIATOR_NAME)
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def test_missing_initiator_name_is_installed_and_iscsid_is_restarted
    assert run_script.success?, @output

    assert_equal INITIATOR_NAME, initiator_name
    assert_includes stub_log, 'systemctl restart iscsid.service'
  end

  def test_changed_initiator_name_is_replaced_and_iscsid_is_restarted
    File.write(initiator_name_path, PACKAGE_INITIATOR_NAME)

    assert run_script.success?, @output

    assert_equal INITIATOR_NAME, initiator_name
    assert_includes stub_log, 'systemctl restart iscsid.service'
  end

  def test_unchanged_initiator_name_does_not_restart_iscsid
    File.write(initiator_name_path, INITIATOR_NAME)

    assert run_script.success?, @output

    refute_includes stub_log, 'systemctl restart'
    # Starts iscsid only if it is not running.
    assert_includes stub_log, 'systemctl start iscsid.service'
  end

  def test_second_run_does_not_restart_iscsid
    assert run_script.success?, @output
    assert run_script.success?, @output

    refute_includes stub_log, 'systemctl restart'
  end

  def test_installed_packages_are_not_upgraded
    assert run_script.success?, @output

    install = stub_log.lines.find { |line| line.start_with?('apt-get install') }
    assert install, stub_log
    assert_includes install.split, '--no-upgrade'
    assert_includes install.split, 'open-iscsi'
  end

  def test_kernel_modules_and_sysctl_are_configured
    assert run_script.success?, @output

    assert_equal "overlay\nbr_netfilter\n", File.read(File.join(@etc_dir, 'modules-load.d', 'porkadot.conf'))
    assert_includes File.read(File.join(@etc_dir, 'sysctl.d', 'k8s.conf')), 'net.ipv4.ip_forward'
    assert_includes stub_log, 'modprobe br_netfilter'
    assert_includes stub_log, 'sysctl --system'
  end

  private

  def render_script
    config_path = write_tmp_config(@tmpdir)
    config = Porkadot::Config.new(config_path)
    config.logger.level = Logger::WARN
    kubelet_default = Porkadot::Assets::KubeletDefault.new(config.kubelet_default)
    kubelet_default.render_erb 'install-pkgs.sh'
    @script = kubelet_default.config.asset_path('install-pkgs.sh')
    @script_dir = File.dirname(@script)
  end

  def write_stubs
    %w(apt-get modprobe sysctl systemctl).each do |name|
      write_stub name, <<~SH
        #!/bin/bash
        echo "#{name} $*" >> "${STUB_LOG}"
      SH
    end
  end

  def write_stub name, body
    path = File.join(@bin_dir, name)
    File.write(path, body)
    File.chmod(0755, path)
  end

  def run_script
    File.write(@log, '')
    env = {
      'PATH' => "#{@bin_dir}:#{ENV['PATH']}",
      'STUB_LOG' => @log,
      'PORKADOT_ETC_DIR' => @etc_dir,
    }
    @output, status = Open3.capture2e(env, 'bash', @script)
    status
  end

  def initiator_name_path
    File.join(@etc_dir, 'iscsi', 'initiatorname.iscsi')
  end

  def initiator_name
    File.read(initiator_name_path)
  end

  def stub_log
    File.read(@log)
  end
end
