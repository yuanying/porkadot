#!/usr/bin/env ruby
# Decides whether the weekly workflow releases porkadot, and if it does,
# bumps the version, commits it and makes the annotated tag in the local
# repository. Pushing is left to the workflow, which pushes the commit and
# the tag together so that neither is left without the other.
#
# A release is made only when every commit since the latest vX.Y.Z tag,
# merge commits aside, was written by Renovate, and they change what goes
# into the gem. Anything the user wrote is released by hand, as before.
#
# Usage: weekly_release.rb [repository]
# The result is written to $GITHUB_OUTPUT when it is set.
require "open3"

module WeeklyRelease
  RENOVATE = "renovate[bot]"
  # What the gem is built from. Workflows, renovate.json, tests and docs do
  # not change what porkadot does, so they alone are not released.
  GEM_FILES = [%r{\Alib/}, %r{\Aexe/}, %r{\Aporkadot\.gemspec\z}]
  TAG = /\Av(\d+)\.(\d+)\.(\d+)\z/

  Decision = Struct.new(:release, :reason, :previous_tag, :version, :subjects, keyword_init: true) do
    def tag
      "v#{version}" if version
    end
  end

  module_function

  def decide(dir)
    tags = git(dir, "tag", "-l").lines.map(&:chomp)
    previous = tags.select { |t| t.match?(TAG) }.max_by { |t| t.match(TAG).captures.map(&:to_i) }
    return no("there is no vX.Y.Z tag") unless previous

    unless system("git", "merge-base", "--is-ancestor", previous, "HEAD", chdir: dir)
      return no("#{previous} is not an ancestor of HEAD")
    end

    range = "#{previous}..HEAD"
    authors = git(dir, "log", "--no-merges", "--format=%an", range).lines.map(&:chomp).uniq
    return no("there are no commits since #{previous}") if authors.empty?
    others = authors - [RENOVATE]
    unless others.empty?
      return no("commits since #{previous} by #{others.join(', ')} are left to a release by hand")
    end

    files = git(dir, "diff", "--name-only", previous, "HEAD").lines.map(&:chomp)
    unless files.any? { |f| GEM_FILES.any? { |re| re.match?(f) } }
      return no("Renovate's commits since #{previous} make no change to the gem")
    end

    major, minor, patch = previous.match(TAG).captures.map(&:to_i)
    subjects = git(dir, "log", "--no-merges", "--reverse", "--format=%s", range).lines.map(&:chomp)
    Decision.new(release: true, reason: "Renovate's commits since #{previous} change the gem",
                 previous_tag: previous, version: "#{major}.#{minor}.#{patch + 1}", subjects: subjects)
  end

  def prepare(dir)
    decision = decide(dir)
    return decision unless decision.release

    version = decision.version
    bump(dir, "lib/porkadot/version.rb", /VERSION = "[^"]+"/, %(VERSION = "#{version}"))
    bump(dir, "docs/spec/README.md", /^- \*\*バージョン\*\*: .+$/, "- **バージョン**: #{version}")
    list = decision.subjects.map { |s| "- #{s}" }.join("\n")
    git(dir, "commit", "-q", "-a", "-F", "-", stdin: <<~MSG)
      Bump version to #{version}

      #{version} includes the dependency updates merged after #{decision.previous_tag}:

      #{list}
    MSG
    git(dir, "tag", "-a", decision.tag, "-F", "-", stdin: <<~MSG)
      Version #{version}

      Renovate's dependency updates since #{decision.previous_tag}:

      #{list}
    MSG
    decision
  end

  def no(reason)
    Decision.new(release: false, reason: reason)
  end

  def bump(dir, path, pattern, replacement)
    file = File.join(dir, path)
    content = File.read(file)
    raise "#{path} has no version to bump" unless content.match?(pattern)
    File.write(file, content.sub(pattern, replacement))
  end

  def git(dir, *args, stdin: "")
    out, err, status = Open3.capture3("git", *args, chdir: dir, stdin_data: stdin)
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?
    out
  end
end

if $PROGRAM_NAME == __FILE__
  decision = WeeklyRelease.prepare(ARGV[0] || Dir.pwd)
  puts decision.release ? "Releasing #{decision.tag}: #{decision.reason}" : "No release: #{decision.reason}"
  if ENV["GITHUB_OUTPUT"]
    File.open(ENV["GITHUB_OUTPUT"], "a") do |f|
      f.puts "release=#{decision.release}"
      f.puts "tag=#{decision.tag}" if decision.release
    end
  end
end
