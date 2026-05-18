# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- **Run tests**: `bundle exec rake test`
- **Run single test**: `bundle exec ruby -Ilib -Itest test/path/to/file_test.rb`
- **Build gem**: `bundle exec rake build`
- **Install gem locally**: `bundle exec rake install`
- **Interactive console**: `bin/console`

## Architecture

Porkadot is a Ruby CLI gem that deploys Kubernetes clusters to bare-metal/VM nodes via SSH.

**Overall flow**: user writes `porkadot.yaml` → `porkadot render` → `porkadot install`

### Layers

**`lib/porkadot/cmd/`** — Thor CLI subcommands. `cli.rb` is the root command; `render/` and `install/` are subcommand groups. Entry point: `exe/porkadot`.

**`lib/porkadot/config.rb` + `lib/porkadot/configs/`** — Configuration layer. `Config` loads user YAML merged with `lib/porkadot/default.yaml` into `Porkadot::Raw` (a `Hashie::Mash`). Each file in `configs/` (certs, kubelet, kubernetes, etcd, bootstrap, addons) wraps `Config` with component-specific typed accessors. The `ConfigUtils` module is mixed into these classes to provide shared path helpers and `method_missing` delegation to raw config.

**`lib/porkadot/assets/`** — ERB template renderers. Each class renders ERB templates (from `assets/` subdirectories) to files in the configured `assets_dir`. `assets.rb` provides `render_erb` and `render_secrets_erb` helpers.

**`lib/porkadot/install/`** — SSHKit-based deployment. Classes SSH into target nodes and deploy the rendered assets. `base.rb` provides the SSHKit DSL setup.

### Config file format

User provides `porkadot.yaml` (default path) with `nodes`, `bootstrap`, `kubernetes`, `etcd`, and `addons` keys. Defaults come from `lib/porkadot/default.yaml`. See `config/porkadot.yaml` for an example.

### Key labels/constants

- `k8s.unstable.cloud/master` — marks a node as a control plane node
- `etcd.unstable.cloud/member` — marks a node as an etcd member
