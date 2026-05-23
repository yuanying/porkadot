# CLI コマンド仕様

## エントリポイント

```
exe/porkadot
```

## グローバルオプション

全コマンドで共通して使用できるオプションです。

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `--config` | `./porkadot.yaml` | 設定ファイルのパス |

---

## `porkadot all`（デフォルトタスク）

`render` と `install` を順に実行します。

```
porkadot [--config <path>]
```

---

## `porkadot render` — アセット生成

設定ファイルを読み込み、証明書・マニフェスト・スクリプト等のアセットを `assets/` ディレクトリに生成します。

### `porkadot render all`（デフォルト）

全アセットを生成します。実行順序: `certs` → `kubelet` → `etcd` → `bootstrap` → `kubernetes`

```
porkadot render [all]
```

### `porkadot render certs`

全 TLS 証明書・秘密鍵を生成します。

```
porkadot render certs [all]
porkadot render certs kubernetes    # Kubernetes PKI + front-proxy PKI
porkadot render certs etcd          # etcd PKI のみ
```

### `porkadot render kubelet`

kubelet 関連ファイルを生成します。

```
porkadot render kubelet [--node <node-name>]
```

| オプション | 説明 |
|-----------|------|
| `--node` | 指定したノードのみ生成（省略時は全ノード） |

生成内容:
- 共通: `install.sh`, `install-deps.sh`, `install-pkgs.sh`, `setup-node.sh`, `setup-containerd.sh`, `ca.crt`
- ノードごと: `kubelet.service`, `config.yaml`, `bootstrap-kubelet.conf`, ブートストラップ証明書

### `porkadot render etcd`

etcd 関連ファイルを生成します。

```
porkadot render etcd [--node <node-name>]
```

| オプション | 説明 |
|-----------|------|
| `--node` | 指定したノードのみ生成（省略時は全 etcd メンバー） |

生成内容: `etcd-server.yaml`, `etcd.env`, `install.sh`, `ca.crt`, `etcd.crt`, `etcd.key`

### `porkadot render bootstrap`

ブートストラップ関連ファイルを生成します。

```
porkadot render bootstrap
```

生成内容: ブートストラップ用静的 Pod マニフェスト（apiserver, controller-manager, scheduler, proxy）, `kubeconfig-bootstrap.yaml`, `install.sh`, `cleanup.sh`

### `porkadot render kubernetes`

Kubernetes コントロールプレーンのマニフェストを生成します。

```
porkadot render kubernetes
```

生成内容: kube-apiserver/controller-manager/scheduler/proxy DaemonSet マニフェスト, kustomization.yaml, アドオンマニフェスト, admin kubeconfig, インストールスクリプト

---

## `porkadot install` — クラスタインストール

レンダリング済みアセットを SSH 経由でノードにデプロイします。

### `porkadot install all`（デフォルト）

クラスタ全体をインストールします。実行順序: `kubelet` → `bootstrap`

```
porkadot install [all]
```

### `porkadot install kubelet`

全ノード（またはの指定ノード）に kubelet をインストールします。

```
porkadot install kubelet [--node <node-name>] [--force]
```

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `--node` | — | 指定したノードのみインストール |
| `--force` | `false` | インストール済みチェックをスキップして強制再インストール |

実行内容: `install-deps.sh` → `install-pkgs.sh` → `install.sh` の順に SSH 実行

### `porkadot install bootstrap` — ブートストラップインストール

#### `porkadot install bootstrap all`（デフォルト）

ブートストラップフェーズを一括実行します。実行順序: `node` → `kubernetes` → `cleanup`

```
porkadot install bootstrap [all]
```

ブートストラップ完了後、ブートストラップノードの kubelet 設定を通常のコントロールプレーンエンドポイントへ戻すには、別途 `porkadot install kubelet` を再実行します。

#### `porkadot install bootstrap node`

ブートストラップノードに一時的なコントロールプレーン（静的 Pod）をデプロイし、起動を待ちます。

```
porkadot install bootstrap node
```

実行内容:
1. ブートストラップ用 kubelet 設定（apiserver エンドポイント: `127.0.0.1:6443`）をデプロイ
2. ブートストラップ用静的 Pod マニフェストを配置
3. `install.sh` を実行
4. `https://127.0.0.1:{bind_port}/readyz` が 200 を返すまでポーリング（5 秒間隔）

#### `porkadot install bootstrap kubernetes`

ブートストラップ apiserver 経由でアドオンとコントロールプレーン DaemonSet をデプロイします。

```
porkadot install bootstrap kubernetes
```

実行内容: MetalLB, Flannel, kube-apiserver DaemonSet, kube-controller-manager DaemonSet, kube-scheduler DaemonSet をデプロイ

#### `porkadot install bootstrap cleanup`

ブートストラップ静的 Pod を削除してクリーンアップします。

```
porkadot install bootstrap cleanup
```

実行内容:
1. 全マスターノードの `/healthz` をポーリングして Ready 確認
2. コントロールプレーンエンドポイント（VIP）の `/healthz` をポーリング
3. VIP が応答したら `cleanup.sh` を実行してブートストラップ静的 Pod を削除

### `porkadot install kubernetes` — Kubernetes コンポーネントインストール

#### `porkadot install kubernetes all`（デフォルト）

全 Kubernetes コンポーネントをインストールします。

```
porkadot install kubernetes [all] [--node <node-name>]
```

#### 個別コンポーネントインストール

```
porkadot install kubernetes apiserver [--node <node-name>]
porkadot install kubernetes controller-manager [--node <node-name>]
porkadot install kubernetes scheduler [--node <node-name>]
porkadot install kubernetes proxy [--node <node-name>]
```

| オプション | 説明 |
|-----------|------|
| `--node` | 指定したノードのみ（省略時はブートストラップノードまたは全コントロールプレーンノード） |

---

## `porkadot etcd` — etcd 操作

### `porkadot etcd backup`

etcd のスナップショットバックアップを取得します。

```
porkadot etcd backup [--node <node-name>] [--path <backup-dir>]
```

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `--node` | — | バックアップ取得ノード（省略時は最初の etcd メンバー） |
| `--path` | `./backup` | バックアップ保存先ディレクトリ |

出力ファイル: `{path}/etcd-{DateTime.now.to_s}.db`

### `porkadot etcd restore`

etcd をスナップショットから復元します。

```
porkadot etcd restore [--path <backup-dir>]
```

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `--path` | `./backup` | バックアップファイルが格納されているディレクトリ |

実行順序: etcd 停止 → 最新バックアップをリストア → etcd 起動

バックアップが見つからない場合はエラーで終了します。

### `porkadot etcd start`

etcd を起動します（`etcd-server.yaml` を manifests ディレクトリに移動）。

```
porkadot etcd start [--node <node-name>]
```

### `porkadot etcd stop`

etcd を停止します（`etcd-server.yaml` を manifests ディレクトリから退避）。

```
porkadot etcd stop [--node <node-name>]
```

---

## `porkadot setup-containerd` — containerd セットアップ

ノードの containerd コンテナランタイムをセットアップします。

```
porkadot setup-containerd [--node <node-name>] [--force] [--bootstrap]
```

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `--node` | — | 指定ノードのみ実行 |
| `--force` | `false` | 強制再セットアップ |
| `--bootstrap` | `false` | ブートストラップノードのみ実行 |

実行内容: `setup-containerd.sh` を SSH 経由で実行

---

## `porkadot setup-node` — ノードデフォルト設定

ノードの OS 設定（ネットワーク、カーネルパラメータ等）を行います。

```
porkadot setup-node [--node <node-name>] [--force] [--bootstrap]
```

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `--node` | — | 指定ノードのみ実行 |
| `--force` | `false` | 強制再実行 |
| `--bootstrap` | `false` | ブートストラップノードのみ実行 |

実行内容: `setup-node.sh` を SSH 経由で実行

---

## `porkadot set-config` — kubeconfig 設定

kubectl の kubeconfig にクラスタ情報を設定します。コントロールプレーンエンドポイント（VIP）向けに切り替えます。

```
porkadot set-config
```
