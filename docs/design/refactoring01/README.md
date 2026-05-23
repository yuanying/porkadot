# porkadot リファクタリング計画 01

## 目的

porkadot の現在の `Config -> Assets -> Install` の3層構造は維持しつつ、層境界を明確にする。

主な改善対象は次の4点である。

- 設定値の暗黙アクセスと可変共有を減らす
- render 時のテンプレート出力基盤を整理する
- install 時の SSH 副作用を事前に検査可能にする
- 既知の etcd アドレス解決バグを先に修正する

この計画では、各変更を独立してレビュー可能な小さいコミット単位に分割する。各詳細設計書は、1ファイルだけ読めば実装内容、テスト内容、非対象範囲が分かる状態にする。

## 全体方針

- 既存CLIの外部挙動は原則維持する。
- `porkadot render` が生成するファイルパスと内容は、明示されたバグ修正を除いて変えない。
- `Hashie::Mash` はすぐに撤廃せず、まず可変共有と `method_missing` 依存を減らす。
- SSHKit の直接実行は残しつつ、実行前に計画を表現できる構造を追加する。
- 各コミットは `bundle exec rake test` が通る単位にする。

## コミット分割

| 順序 | 設計書 | 目的 |
|------|--------|------|
| 1 | [01-fix-etcd-addressing.md](01-fix-etcd-addressing.md) | etcd listen/peer address 周りの既知バグを修正する |
| 2 | [02-remove-config-mutation.md](02-remove-config-mutation.md) | 設定派生メソッドが `raw` を変更しないようにする |
| 3 | [03-add-config-validator.md](03-add-config-validator.md) | render/install 前の設定検証を追加する |
| 4 | [04-replace-implicit-config-access.md](04-replace-implicit-config-access.md) | `method_missing` 依存を明示アクセサへ段階移行する |
| 5 | [05-extract-asset-renderer.md](05-extract-asset-renderer.md) | ERB rendering と file output の共通基盤を切り出す |
| 6 | [06-add-addon-registry.md](06-add-addon-registry.md) | addon manifest 登録を明示的な registry にする |
| 7 | [07-introduce-install-plan.md](07-introduce-install-plan.md) | install の操作列を dry-run 可能な計画として表現する |
| 8 | [08-clean-docs-and-spec-sync.md](08-clean-docs-and-spec-sync.md) | 実装後の仕様差分を既存docsへ反映する |
| 9 | [09-support-containerd-v1-v2.md](09-support-containerd-v1-v2.md) | containerd v1/v2 の設定差分を安全に扱う |

## 推奨順序

上の表の順に実装する。

最初に etcd の明確なバグを修正し、次に設定オブジェクトの可変状態を減らす。その後で validator と明示アクセサを追加すると、後続の renderer / registry / install plan の変更で前提が安定する。

`07-introduce-install-plan` は最も影響範囲が大きいため、config と assets の境界整理後に実施する。

`09-support-containerd-v1-v2` は既存 node の containerd 設定を壊さないことが重要なため、`setup-containerd` の現状挙動を確認したうえで独立して実施できる。

## 全体テスト方針

- 各コミットで `bundle exec rake test` を実行する。
- 生成物の内容が変わる可能性がある変更では、最小限の render テストを追加する。
- install 周りでは実SSHを使わず、生成される操作列または呼び出し対象を検査する。
- 既存 fixture は互換性確認として残し、不正設定用 fixture は validator 追加時に増やす。

## 完了条件

- 9本の詳細設計に沿って実装されている。
- 既存CLI互換を壊す変更は、各設計書の互換性欄に記載された範囲に収まっている。
- `bundle exec rake test` が通る。
- `docs/spec/` と実装の差分が `08-clean-docs-and-spec-sync` で解消されている。
