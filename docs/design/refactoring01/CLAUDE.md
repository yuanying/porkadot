# Refactoring01 Implementation Notes

## Required assets regression check

For every implementation based on files in `docs/design/refactoring01`, verify
that rendering with `../porkadot.yaml` does not unintentionally change generated
assets.

`assets/` is outside Git tracking, so do not use `git diff -- assets` for this
check. Instead:

1. Confirm current state.
   - `git status --short --branch`
   - `git ls-files assets` should be empty.
2. Back up the current generated assets into `/tmp`.
   - `tmp_before=$(mktemp -d /tmp/porkadot-assets-before.XXXXXX)`
   - `cp -a assets "$tmp_before/assets"`
3. Render deterministic asset groups with the real config.
   - `bundle exec exe/porkadot --config ../porkadot.yaml render kubelet`
   - `bundle exec exe/porkadot --config ../porkadot.yaml render etcd`
   - `bundle exec exe/porkadot --config ../porkadot.yaml render bootstrap`
   - `bundle exec exe/porkadot --config ../porkadot.yaml render kubernetes`
4. Compare generated assets.
   - `diff -ru "$tmp_before/assets" assets`
5. Restore the original assets before finishing.
   - Remove the regenerated `assets/`.
   - Copy `"$tmp_before/assets"` back to `assets`.
   - Re-run `diff -ru "$tmp_before/assets" assets` to confirm restoration.

Do not run `render all` or `render certs` for this regression check.
Certificate/key files may be refreshed or regenerated and can produce unrelated
diffs.

If the asset diff is not empty, inspect whether the change is intended by the
current design document. Do not commit regenerated `assets/` unless explicitly
requested.
