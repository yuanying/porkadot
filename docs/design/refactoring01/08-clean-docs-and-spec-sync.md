# 08. docs/spec との同期

## 目的

リファクタリング実装後に、既存仕様書と実装の差分を解消する。

このコミットはコード変更を原則含めず、ドキュメント整備に限定する。

## 背景 / 現状の問題

`docs/spec/` はporkadotの仕様をまとめているが、今回のリファクタリングで次の仕様が変わる。

- etcd peer listen label の正しい名前
- 設定検証のタイミングとエラー方針
- unknown addon の扱い
- `porkadot install kubernetes --dry-run`
- asset rendererやaddon registry導入後の内部構造

実装後にdocsが古いままだと、次の変更者が誤った前提で作業する可能性がある。

## 変更対象

- `docs/spec/01-architecture.md`
- `docs/spec/02-config.md`
- `docs/spec/03-cli.md`
- `docs/spec/04-deploy-flow.md`
- `docs/spec/06-assets.md`
- `docs/spec/07-addons.md`
- 必要に応じて `README.md`

## 実装方針

`docs/spec/01-architecture.md`:

- `ETCD_LISTEN_PEER_ADDRESS_LABEL` の値を `etcd.unstable.cloud/listen-peer-address` に更新する。
- legacy fallbackとして `etcd.unstable.cloud/listen-client-address` が扱われることを注記する。
- `Config -> Assets -> Install` の説明に、validator、renderer、addon registry、install planを追記する。

`docs/spec/02-config.md`:

- `nodes.*.labels.etcd.unstable.cloud/listen-peer-address` を追加する。
- `listen-client-address` はclient用であり、peer用legacy fallbackは非推奨であることを書く。
- 設定検証で検出される代表的なエラーを追加する。
- unknown addonがエラーになることを明記する。

`docs/spec/03-cli.md`:

- `porkadot install kubernetes --dry-run` を追加する。
- render/installの入口でconfig validationが走ることを書く。

`docs/spec/04-deploy-flow.md`:

- install kubernetesの前にdry-runで操作列を確認できることを追記する。

`docs/spec/06-assets.md`:

- 内部実装として `Assets::Renderer` が通常出力とsecret出力を担うことを追記する。
- 出力ディレクトリ構成は変えない。

`docs/spec/07-addons.md`:

- addon定義が `AddonRegistry` で管理されることを追記する。
- 既知addon一覧と unknown addon の扱いを更新する。

`README.md`:

- ユーザー向けに意味がある変更だけ反映する。
- 具体的にはdry-runとconfig validationの説明を短く追加する。

## 互換性

- docs更新のみ。
- コード挙動は変更しない。

## テスト計画

コードテストは不要。

確認項目:

- 古い peer label 説明が残っていない。
- dry-run CLIの記述が `docs/spec/03-cli.md` と `docs/spec/04-deploy-flow.md` で矛盾していない。
- addon一覧が `AddonRegistry` の実装と一致している。
- READMEに実装されていない将来機能を書いていない。

## 完了条件

- 実装後の仕様とdocs/specが一致している。
- 既知の古い記述が更新されている。
- READMEにはユーザー影響のある変更だけが簡潔に反映されている。

## このコミットでやらないこと

- コード変更はしない。
- 新しい設計方針の追加はしない。
- 未実装機能を仕様として書かない。

