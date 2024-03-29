
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "porkadot/version"

Gem::Specification.new do |spec|
  spec.name          = "porkadot"
  spec.version       = Porkadot::VERSION
  spec.authors       = ["OTSUKA, Yuanying"]
  spec.email         = ["yuanying@fraction.jp"]

  spec.summary       = "Porkadot is a CLI tool to deploy Kubernetes cluster."
  spec.description   = "The kubernetes installer for those who want to install k8s in your home."
  spec.homepage      = "https://github.com/yuanying/porkadot"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["homepage_uri"] = spec.homepage
    spec.metadata["source_code_uri"] = "https://github.com/yuanying/porkadot"
    spec.metadata["changelog_uri"] = "https://github.com/yuanying/porkadot/master/CHANGELOG.md"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.0"
  spec.add_dependency "hashie", "~> 4.1"
  spec.add_dependency "sshkit", "~> 1.20"
  spec.add_dependency "net-ssh", "= 7.0.1"
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
