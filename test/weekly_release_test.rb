require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../.github/scripts/weekly_release"

# Each test builds a small repository with the files the release bumps,
# tags it, and adds commits after the tag as the user or as Renovate.
class WeeklyReleaseTest < Minitest::Test
  USER = ["OTSUKA, Yuanying", "yuanying@fraction.jp"]
  RENOVATE = ["renovate[bot]", "29139614+renovate[bot]@users.noreply.github.com"]

  def setup
    @dir = Dir.mktmpdir
    git "init", "-q", "-b", "master"
    git "config", "user.name", "github-actions[bot]"
    git "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"
    write "lib/porkadot/version.rb", %(module Porkadot\n  VERSION = "0.34.1"\nend\n)
    write "docs/spec/README.md", "# porkadot\n\n- **バージョン**: 0.34.1\n- **言語**: Ruby\n"
    write "lib/porkadot/default.yaml", "etcd: v3.6.10\n"
    commit USER, "Bump version to 0.34.1"
    git "tag", "-a", "v0.34.1", "-m", "Version 0.34.1"
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_releases_renovate_updates_of_the_gem
    write "lib/porkadot/default.yaml", "etcd: v3.6.11\n"
    commit RENOVATE, "chore(deps): update registry.k8s.io/etcd to v3.6.11"
    write "porkadot.gemspec", "# thor 1.4\n"
    commit RENOVATE, "chore(deps): update dependency thor to v1.4.0"

    decision = WeeklyRelease.prepare(@dir)

    assert decision.release, decision.reason
    assert_equal "v0.34.1", decision.previous_tag
    assert_equal "0.34.2", decision.version
    assert_equal "v0.34.2", decision.tag
    assert_includes read("lib/porkadot/version.rb"), %(VERSION = "0.34.2")
    assert_includes read("docs/spec/README.md"), "- **バージョン**: 0.34.2\n"
    assert_equal "", git("status", "--porcelain")
    assert_equal "Bump version to 0.34.2", git("log", "-1", "--format=%s")
    assert_equal "tag", git("cat-file", "-t", "v0.34.2")
    assert_equal git("rev-parse", "HEAD"), git("rev-parse", "v0.34.2^{commit}")
    message = git("tag", "-l", "--format=%(contents)", "v0.34.2")
    assert_match(/\AVersion 0\.34\.2\n/, message)
    assert_includes message, "dependency updates"
    assert_includes message, "- chore(deps): update registry.k8s.io/etcd to v3.6.11\n" \
                             "- chore(deps): update dependency thor to v1.4.0"
  end

  def test_does_not_release_when_the_user_committed
    write "lib/porkadot/default.yaml", "etcd: v3.6.11\n"
    commit RENOVATE, "chore(deps): update registry.k8s.io/etcd to v3.6.11"
    write "lib/porkadot/cli.rb", "# new feature\n"
    commit USER, "Add a feature"

    assert_no_release(/OTSUKA, Yuanying/)
  end

  def test_does_not_release_changes_outside_the_gem
    write ".github/workflows/ci.yml", "name: CI\n"
    commit RENOVATE, "chore(deps): update github-actions"
    write "renovate.json", "{}\n"
    commit RENOVATE, "chore(deps): update renovate config"

    assert_no_release(/no change to the gem/)
  end

  def test_ignores_merge_commits
    git "checkout", "-q", "-b", "renovate/etcd"
    write "lib/porkadot/default.yaml", "etcd: v3.6.11\n"
    commit RENOVATE, "chore(deps): update registry.k8s.io/etcd to v3.6.11"
    git "checkout", "-q", "master"
    env = { "GIT_AUTHOR_NAME" => USER[0], "GIT_AUTHOR_EMAIL" => USER[1] }
    git "merge", "-q", "--no-ff", "-m", "Merge pull request #1", "renovate/etcd", env: env

    assert WeeklyRelease.decide(@dir).release
  end

  def test_picks_the_latest_three_part_tag
    write "lib/porkadot/default.yaml", "etcd: v3.6.11\n"
    commit RENOVATE, "chore(deps): update registry.k8s.io/etcd to v3.6.11"
    git "tag", "-a", "v0.9.0", "-m", "Version 0.9.0", "HEAD~1"
    git "tag", "-a", "v0.34.1.1", "-m", "four parts", "HEAD"
    git "tag", "-a", "v0.35.0-rc1", "-m", "pre-release", "HEAD"

    decision = WeeklyRelease.decide(@dir)

    assert decision.release, decision.reason
    assert_equal "v0.34.1", decision.previous_tag
    assert_equal "v0.34.2", decision.tag
  end

  def test_does_not_release_without_a_tag
    git "tag", "-d", "v0.34.1"
    write "lib/porkadot/default.yaml", "etcd: v3.6.11\n"
    commit RENOVATE, "chore(deps): update registry.k8s.io/etcd to v3.6.11"

    assert_no_release(/no vX\.Y\.Z tag/)
  end

  def test_does_not_release_without_commits_since_the_tag
    assert_no_release(/no commits/)
  end

  def test_does_not_release_from_a_tag_off_the_branch
    git "checkout", "-q", "-b", "other"
    write "lib/porkadot/other.rb", "# other\n"
    commit USER, "Something else"
    git "tag", "-a", "v0.35.0", "-m", "Version 0.35.0"
    git "checkout", "-q", "master"
    write "lib/porkadot/default.yaml", "etcd: v3.6.11\n"
    commit RENOVATE, "chore(deps): update registry.k8s.io/etcd to v3.6.11"

    assert_no_release(/v0\.35\.0 is not an ancestor/)
  end

  private

  def assert_no_release(reason)
    head = git("rev-parse", "HEAD")
    tags = git("tag", "-l")
    decision = WeeklyRelease.prepare(@dir)
    refute decision.release
    assert_match reason, decision.reason
    assert_equal head, git("rev-parse", "HEAD")
    assert_equal tags, git("tag", "-l")
    assert_equal "", git("status", "--porcelain")
  end

  def write(path, content)
    file = File.join(@dir, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, content)
  end

  def read(path)
    File.read(File.join(@dir, path))
  end

  def commit(author, subject)
    git "add", "-A"
    env = { "GIT_AUTHOR_NAME" => author[0], "GIT_AUTHOR_EMAIL" => author[1] }
    git "commit", "-q", "-m", subject, env: env
  end

  def git(*args, env: {})
    out, status = Open3.capture2e(env, "git", *args, chdir: @dir)
    raise "git #{args.join(' ')} failed: #{out}" unless status.success?
    out.chomp
  end
end
