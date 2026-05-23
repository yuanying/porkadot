# porkadot 仕様書

## 概要

**porkadot** は、SSH 経由で Kubernetes クラスタをベアメタル/VM ノードにデプロイする Ruby CLI ツールです。ホームラボや小規模なプライベートクラウド環境向けに設計されており、設定ファイル（`porkadot.yaml`）を記述するだけで、証明書生成からコントロールプレーンのデプロイまでを自動化します。

- **バージョン**: 0.29.0
- **言語**: Ruby
- **ライセンス**: —
- **リポジトリ**: https://github.com/yuanying/porkadot

## 特徴

- YAML 設定ファイル一つでクラスタトポロジを定義
- TLS 証明書の自動生成（Kubernetes PKI / etcd PKI / front-proxy PKI）
- bootkube アーキテクチャによる self-hosted Kubernetes（コントロールプレーンが Deployment として動作）
- SSHKit による SSH 経由のリモートデプロイ
- MetalLB による LoadBalancer サービス対応
- デュアルスタック（IPv4/IPv6）ネットワーク対応

## 依存ライブラリ

| gem | バージョン | 用途 |
|-----|-----------|------|
| thor | ~> 1.0 | CLI フレームワーク |
| hashie | >= 4.1 | YAML 設定の Mash 化 |
| sshkit | ~> 1.20 | SSH 実行 |
| net-ssh | ~> 7.0 | SSH プロトコル |

## 基本ワークフロー

```
porkadot.yaml 作成 → porkadot render → porkadot install
```

1. `porkadot.yaml` にノード構成・クラスタ設定を記述する
2. `porkadot render` で証明書・マニフェスト・スクリプト等のアセットを生成する
3. `porkadot install` で SSH 経由でノードにデプロイする

## 目次

| ファイル | 内容 |
|---------|------|
| [01-architecture.md](01-architecture.md) | アーキテクチャ（3層構造・全体フロー・ノードラベル） |
| [02-config.md](02-config.md) | 設定ファイル仕様（`porkadot.yaml` 全セクション） |
| [03-cli.md](03-cli.md) | CLI コマンド仕様（全コマンド・サブコマンド・オプション） |
| [04-deploy-flow.md](04-deploy-flow.md) | デプロイフロー（詳細手順・注意事項・リカバリ） |
| [05-certificates.md](05-certificates.md) | 証明書管理（PKI 構造・有効期限・SAN 設定） |
| [06-assets.md](06-assets.md) | 生成アセット（ディレクトリ構成・各ファイルの説明） |
| [07-addons.md](07-addons.md) | アドオン仕様・etcd 操作 |
