# Porkadot

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/porkadot`. To experiment with that code, run `bin/console` for an interactive prompt.

TODO: Delete this and the text above, and describe your gem

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'porkadot'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install porkadot

## Usage

TODO: Write usage instructions here

## Secrets and sops

porkadot renders certificates, private keys, kubeconfigs and secret manifests into the same `assets/<group>/...` tree as the other assets, with mode 0600.

To keep the assets directory in git, set `local.sops.enabled: true` in `porkadot.yaml`. Secrets are then encrypted with [sops](https://github.com/getsops/sops) (binary format) using the `creation_rules` of `.sops.yaml` next to `porkadot.yaml`, or of `local.sops.config`. They are decrypted in memory when porkadot reads them, including when it uploads them to nodes, so plain secrets are never written to the local disk.

```yaml
local:
  sops:
    enabled: true
```

Assets rendered by older versions keep secrets in `assets/secrets/`. Move them with `porkadot migrate-secrets --config porkadot.yaml`, then run `render kubelet`, `render etcd`, `render bootstrap` and `render kubernetes`. Most commands refuse to run until the old tree is migrated.

See `docs/design/sops-secrets/README.md` for the design.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/yuanying/porkadot.
