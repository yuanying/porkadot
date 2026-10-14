require "test_helper"
require "tmpdir"
require "fileutils"
require "open3"

class PorkadotAssetsSetupContainerdTest < Minitest::Test
  include Porkadot::TestUtils

  CONTAINERD_FIXTURES_DIR = File.join(TEST_FIXTURES_DIR, 'containerd')
  V1_VERSION = 'containerd github.com/containerd/containerd 1.7.12'
  V2_VERSION = 'containerd github.com/containerd/containerd/v2 2.2.1'
  V1_RUNC_OPTIONS = '[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]'
  V2_RUNC_OPTIONS = "[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]"

  def setup
    @tmpdir = Dir.mktmpdir
    @etc_dir = File.join(@tmpdir, 'etc', 'containerd')
    @bin_dir = File.join(@tmpdir, 'bin')
    @log = File.join(@tmpdir, 'stub.log')
    FileUtils.mkdir_p(@bin_dir)
    write_stubs
    render_script
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def test_v1_generates_default_config_with_systemd_cgroup
    status = run_script(version: V1_VERSION, default: 'v1-default.toml')

    assert status.success?, @output
    assert_equal 'true', systemd_cgroup(config, V1_RUNC_OPTIONS)
    assert_match(/^version = 2$/, config)
    assert_includes stub_log, 'systemctl restart containerd'
  end

  def test_v2_generates_default_config_with_systemd_cgroup
    status = run_script(version: V2_VERSION, default: 'v2-default.toml')

    assert status.success?, @output
    assert_match(/^version = 3$/, config)
    assert_equal 'true', systemd_cgroup(config, V2_RUNC_OPTIONS)
    assert_includes config, "imports = ['/etc/containerd/conf.d/*.toml']"
    assert_includes stub_log, 'systemctl restart containerd'
  end

  def test_existing_config_is_not_regenerated
    existing = fixture('v2-nvidia.toml')
    install_existing_config(existing)

    status = run_script(version: V2_VERSION, default: 'v2-default.toml')

    assert status.success?, @output
    refute_includes stub_log, 'containerd config default'
    assert_equal existing.sub(/(runc\.options\]\n\s+BinaryName = ''\n\s+)SystemdCgroup = false/, '\1SystemdCgroup = true'), config
  end

  def test_imports_and_other_runtimes_are_preserved
    install_existing_config(fixture('v2-nvidia.toml'))

    status = run_script(version: V2_VERSION, default: 'v2-default.toml')

    assert status.success?, @output
    assert_includes config, "imports = ['/etc/containerd/conf.d/*.toml', '/etc/containerd/conf.d/99-nvidia.toml']"
    assert_equal 'true', systemd_cgroup(config, V2_RUNC_OPTIONS)
    nvidia_options = "[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nvidia.options]"
    assert_equal 'false', systemd_cgroup(config, nvidia_options)
  end

  def test_v1_inserts_systemd_cgroup_into_existing_runc_options
    install_existing_config(fixture('v1-without-systemd-cgroup.toml'))

    status = run_script(version: V1_VERSION, default: 'v1-default.toml')

    assert status.success?, @output
    assert_equal 'true', systemd_cgroup(config, V1_RUNC_OPTIONS)
    nvidia_options = '[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]'
    assert_equal 'false', systemd_cgroup(config, nvidia_options)
    assert_includes config, 'imports = ["/etc/containerd/conf.d/*.toml"]'
    assert_equal 1, config.scan(V1_RUNC_OPTIONS).size
  end

  def test_v1_fails_without_creating_runc_options_section_when_missing
    existing = fixture('v1-without-runc-options.toml')
    install_existing_config(existing)

    status = run_script(version: V1_VERSION, default: 'v1-default.toml')

    refute status.success?
    assert_equal existing, config
    assert_missing_section_error V1_RUNC_OPTIONS
    refute_includes stub_log, 'systemctl restart containerd'
  end

  def test_v2_fails_without_creating_runc_section_when_missing
    existing = fixture('v2-without-runc.toml')
    install_existing_config(existing)

    status = run_script(version: V2_VERSION, default: 'v2-default.toml')

    refute status.success?
    assert_equal existing, config
    assert_missing_section_error V2_RUNC_OPTIONS
    refute_includes stub_log, 'systemctl restart containerd'
  end

  def test_runc_options_inline_table_is_not_supported
    existing = fixture('v2-inline-table.toml')
    install_existing_config(existing)

    status = run_script(version: V2_VERSION, default: 'v2-default.toml')

    refute status.success?
    assert_equal existing, config
    assert_missing_section_error V2_RUNC_OPTIONS
    refute_includes stub_log, 'systemctl restart containerd'
  end

  def test_v1_section_header_with_trailing_comment
    install_existing_config(fixture('v1-header-comment.toml'))

    status = run_script(version: V1_VERSION, default: 'v1-default.toml')

    assert status.success?, @output
    assert_equal 'true', systemd_cgroup(config, V1_RUNC_OPTIONS)
    assert_includes config, "#{V1_RUNC_OPTIONS} # runc options"
    assert_equal 1, config.scan('SystemdCgroup').size
  end

  def test_v2_section_header_with_trailing_comment
    install_existing_config(fixture('v2-header-comment.toml'))

    status = run_script(version: V2_VERSION, default: 'v2-default.toml')

    assert status.success?, @output
    assert_equal 'true', systemd_cgroup(config, V2_RUNC_OPTIONS)
    assert_includes config, "#{V2_RUNC_OPTIONS}#runc options"
  end

  def test_v2_binary_with_version2_config_uses_v1_path
    install_existing_config(fixture('v1-without-systemd-cgroup.toml'))

    status = run_script(version: V2_VERSION, default: 'v2-default.toml')

    assert status.success?, @output
    assert_equal 'true', systemd_cgroup(config, V1_RUNC_OPTIONS)
    refute_includes config, V2_RUNC_OPTIONS
  end

  def test_v1_binary_with_version3_config_fails
    install_existing_config(fixture('v2-default.toml'))

    status = run_script(version: V1_VERSION, default: 'v1-default.toml')

    refute status.success?
    refute_includes stub_log, 'systemctl restart containerd'
  end

  def test_config_without_version_is_regenerated
    existing = fixture('unversioned.toml')
    install_existing_config(existing)

    status = run_script(version: V1_VERSION, default: 'v1-default.toml')

    assert status.success?, @output
    assert_match(/^version = 2$/, config)
    assert_equal 'true', systemd_cgroup(config, V1_RUNC_OPTIONS)
    assert_equal [existing], backups.map { |f| File.read(f) }
    assert_includes stub_log, 'systemctl restart containerd'
  end

  def test_containerd_io_config_is_regenerated_with_v1
    existing = fixture('containerd-io.toml')
    install_existing_config(existing)

    status = run_script(version: V1_VERSION, default: 'v1-default.toml')

    assert status.success?, @output
    assert_includes stub_log, 'containerd config default'
    assert_match(/^version = 2$/, config)
    refute_includes config, 'disabled_plugins = ["cri"]'
    assert_equal 'true', systemd_cgroup(config, V1_RUNC_OPTIONS)
    assert_equal 1, backups.size
    assert_match(/config\.toml\.porkadot-bak\.\d{14}\z/, backups.first)
    assert_equal existing, File.read(backups.first)
    assert_match(/Regenerat/, @output)
    assert_includes stub_log, 'systemctl restart containerd'
  end

  def test_containerd_io_config_is_regenerated_with_v2
    existing = fixture('containerd-io.toml')
    install_existing_config(existing)

    status = run_script(version: V2_VERSION, default: 'v2-default.toml')

    assert status.success?, @output
    assert_includes stub_log, 'containerd config default'
    assert_match(/^version = 3$/, config)
    assert_equal 'true', systemd_cgroup(config, V2_RUNC_OPTIONS)
    assert_equal [existing], backups.map { |f| File.read(f) }
    assert_includes stub_log, 'systemctl restart containerd'
  end

  def test_versioned_config_is_not_backed_up
    install_existing_config(fixture('v2-nvidia.toml'))

    status = run_script(version: V2_VERSION, default: 'v2-default.toml')

    assert status.success?, @output
    assert_empty backups
  end

  def test_unknown_config_version_fails
    install_existing_config(fixture('v2-default.toml').sub(/^version = 3$/, 'version = 4'))

    status = run_script(version: V2_VERSION, default: 'v2-default.toml')

    refute status.success?
    assert_match(/Unsupported containerd config version/, @output)
    assert_empty backups
    refute_includes stub_log, 'systemctl restart containerd'
  end

  def test_unsupported_major_version_fails
    status = run_script(version: 'containerd github.com/containerd/containerd/v3 3.0.0', default: 'v2-default.toml')

    refute status.success?
    assert_match(/Unsupported containerd major version/, @output)
    refute_includes stub_log, 'systemctl restart containerd'
  end

  def test_user_provided_config_is_copied_as_is
    user_config = fixture('v2-without-runc.toml')
    FileUtils.mkdir_p(File.join(@script_dir, 'containerd'))
    File.write(File.join(@script_dir, 'containerd', 'config.toml'), user_config)
    install_existing_config(fixture('v2-nvidia.toml'))

    status = run_script(version: V2_VERSION, default: 'v2-default.toml')

    assert status.success?, @output
    assert_equal user_config, config
    assert_includes stub_log, 'systemctl restart containerd'
  end

  def test_running_twice_is_idempotent
    [V1_VERSION, V2_VERSION].zip(['v1-default.toml', 'v2-default.toml']).each do |version, default|
      FileUtils.rm_rf(@etc_dir)
      assert run_script(version: version, default: default).success?, @output
      first = config
      assert run_script(version: version, default: default).success?, @output
      assert_equal first, config
    end
  end

  private

  def render_script
    config = YAML.load_file(File.join(TEST_FIXTURES_DIR, 'config', 'porkadot.yaml'))
    config['local'] = { 'assets_dir' => File.join(@tmpdir, 'assets') }
    config_path = File.join(@tmpdir, 'porkadot.yaml')
    File.write(config_path, YAML.dump(config))

    kubelet_default = Porkadot::Assets::KubeletDefault.new(Porkadot::Config.new(config_path).kubelet_default)
    capture_io { kubelet_default.render_erb 'setup-containerd.sh' }
    @script = kubelet_default.config.asset_path('setup-containerd.sh')
    @script_dir = File.dirname(@script)
  end

  def write_stubs
    write_stub 'containerd', <<~'SH'
      #!/bin/bash
      echo "containerd $*" >> "${STUB_LOG}"
      case "$1" in
        --version) echo "${STUB_CONTAINERD_VERSION}" ;;
        config) cat "${STUB_CONTAINERD_DEFAULT}" ;;
        *) exit 1 ;;
      esac
    SH
    write_stub 'systemctl', <<~'SH'
      #!/bin/bash
      echo "systemctl $*" >> "${STUB_LOG}"
    SH
  end

  def write_stub name, body
    path = File.join(@bin_dir, name)
    File.write(path, body)
    File.chmod(0755, path)
  end

  def run_script version:, default:
    File.write(@log, '')
    env = {
      'PATH' => "#{@bin_dir}:#{ENV['PATH']}",
      'STUB_LOG' => @log,
      'STUB_CONTAINERD_VERSION' => version,
      'STUB_CONTAINERD_DEFAULT' => File.join(CONTAINERD_FIXTURES_DIR, default),
      'PORKADOT_CONTAINERD_CONFIG_DIR' => @etc_dir,
    }
    @output, status = Open3.capture2e(env, 'bash', @script)
    status
  end

  def fixture name
    File.read(File.join(CONTAINERD_FIXTURES_DIR, name))
  end

  def install_existing_config content
    FileUtils.mkdir_p(@etc_dir)
    File.write(File.join(@etc_dir, 'config.toml'), content)
  end

  def config
    File.read(File.join(@etc_dir, 'config.toml'))
  end

  def backups
    Dir.glob(File.join(@etc_dir, 'config.toml.porkadot-bak.*'))
  end

  def assert_missing_section_error section
    assert_match(/ERROR: .*not found/, @output)
    assert_includes @output.gsub("'", '"'), section.gsub("'", '"')
    assert_match(/inline table/, @output)
    assert_match(/porkadot-bak|back up|move/i, @output)
  end

  def stub_log
    File.read(@log)
  end

  # Returns the SystemdCgroup value set directly under the given section header.
  def systemd_cgroup content, header
    in_section = false
    content.each_line do |line|
      stripped = line.sub(/\s*#.*$/, '').strip
      if stripped.start_with?('[')
        in_section = (stripped == header)
        next
      end
      return $1 if in_section && stripped =~ /\ASystemdCgroup\s*=\s*(\S+)/
    end
    nil
  end
end
