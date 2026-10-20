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

生成内容: ブートストラップ用静的 Pod マニフェスト（apiserver, controller-manager, scheduler, proxy）, `kubeconfig-bootstrap.yaml`, `install.sh`, `cleanup.sh`, `bootstrap/secrets/`（証明書・鍵のコピー）

`assets/certs/` に無い証明書・鍵は生成し、既存のものは作り直しません。`render certs` を先に実行する必要はありません。

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
| `--force` | `false` | ノードにある版を使わず、kubectl・kubelet・etcdctl・etcdutl・crictl・CNI plugins をすべてダウンロードし直す |

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

実行内容: MetalLB, CNI（Flannel または cnidaria）, kube-apiserver DaemonSet, kube-controller-manager DaemonSet, kube-scheduler DaemonSet をデプロイ

#### `porkadot install bootstrap cleanup`

ブートストラップ静的 Pod を削除してクリーンアップします。

```
porkadot install bootstrap cleanup [--timeout <秒>]
```

| オプション | 説明 |
|---|---|
| `--timeout` | 1〜3 の待ちの上限（秒、既定 600）。5 の待ちにも同じ上限を使う |

実行内容（ポーリングは 5 秒間隔）:
1. 全マスターノードの `https://<master>:<bind_port>/readyz` が 200 を返すまで待つ
2. ブートストラップ apiserver（`127.0.0.1`）に問い合わせ、Service `kube-system/porkadot-kubernetes`（VIP の背後）の EndpointSlice に、全マスターの kube-apiserver の endpoint が `ready` で入るまで待つ。ブートストラップ apiserver 自身の endpoint は数えない
3. Deployment `kube-controller-manager` と `kube-scheduler` に Ready のレプリカが 1 つ以上あるまで待つ
4. `cleanup.sh` を実行してブートストラップ静的 Pod を削除
5. VIP の `/readyz` が応答するまで待つ

1〜3 が上限までに揃わなければ、静的 Pod を消さずにエラーで止まり、何が揃っていないかと確かめるコマンドを表示します。5 が上限までに応答しなければ、`install bootstrap node` からやり直す手順を表示してエラーで止まります。

### `porkadot install kubernetes` — Kubernetes コンポーネントインストール

#### `porkadot install kubernetes all`（デフォルト）

全 Kubernetes コンポーネントをインストールします。

```
porkadot install kubernetes [all] [--node <node-name>] [--apiserver-timeout <秒>]
```

kube-apiserver を先に適用し、DaemonSet `kube-apiserver` の rollout が終わるのを待ってから、kube-controller-manager・kube-scheduler・kube-proxy・アドオンを適用します（[06-assets.md](06-assets.md) の `kubernetes/install.sh`）。
`--apiserver-timeout`（既定 600 秒）までに rollout が終わらなければ、残りを適用せずにエラーで止まります。kube-apiserver の Pod を確かめてから、もう一度実行します。
`install bootstrap kubernetes` は待たずに一度に適用します。

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
| `--node` | — | バックアップ取得ノード。`porkadot.yaml` の `nodes` のキーで指定する（省略時は最初の etcd メンバー） |
| `--path` | `./backup` | バックアップ保存先ディレクトリ |

出力ファイル: `{path}/etcd-{DateTime.now.to_s}.db`

### `porkadot etcd restore`

etcd をスナップショットから復元します。

```
porkadot etcd restore [--path <backup-dir>] [--timeout <秒>] [--bump-revision <幅>]
```

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `--path` | `./backup` | バックアップファイルが格納されているディレクトリ |
| `--timeout` | `600` | リストアの後、etcd の health と各コントロールプレーンのコンポーネントの入れ替えをそれぞれ待つ秒数 |
| `--bump-revision` | なし | revision を進める幅。指定すると今の etcd の revision を読まずにこの値を使う。動いている etcd から revision を読めないときに使う |

実行順序: 今の etcd の revision を読む → etcd 停止 → 最新バックアップをリストア → etcd 起動 → 全メンバーの health を待つ → kube-apiserver・kube-controller-manager・kube-scheduler を入れ替える

各 etcd メンバーで、既存の `/var/lib/etcd` を `/opt/porkadot/data-<日時>` に退避し、
`etcd-server.yaml` と同じメンバー名・peer URL・initial-cluster を使って `/var/lib/etcd` に復元する。
復元には `/opt/bin/etcdutl snapshot restore` を使う（etcdctl の `snapshot restore` は 3.6 で消えた）。
revision は `--bump-revision <幅> --mark-compacted` で進めて compacted にする（etcd 3.5.10 以上）。
幅は「1000000000」と「今の revision − snapshot の revision + 1000000000」の大きい方（詳細は [07-addons.md](07-addons.md#リストア)）。
どのメンバーからも今の revision を読めず `--bump-revision` も無いときは、etcd を止める前にエラーで終了する。

バックアップが見つからない場合はエラーで終了します。

### `porkadot etcd start`

etcd を起動します（`etcd-server.yaml` を manifests ディレクトリに移動）。

```
porkadot etcd start [--node <node-name>]
```

`--node` には `porkadot.yaml` の `nodes` のキーを指定する。そのノードの接続設定（`connection`）で接続する。
定義にないノードや etcd メンバーでないノードを指定するとエラーになる。stop / backup も同じ。

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

## `porkadot migrate-secrets` — secret の移行

以前の porkadot が `assets/secrets/<group>/...` に出力した secret を、`assets/<group>/...` へ移動します。`local.sops.enabled: true` なら移動と同時に暗号化します。

```
porkadot migrate-secrets [--config <path>]
```

- 移動先に内容の異なるファイルがある場合は、何も変更せずにエラーで終了します。
- `assets/secrets/` が残っている間、`render`・`install`・`rotate-certs`・`set-config`・`setup-node`・`setup-containerd` はエラーで止まります（`etcd` サブコマンドは止まりません）。
- 移行後は `render kubelet`・`render etcd`・`render bootstrap`・`render kubernetes` を実行し、新しいレイアウト用のスクリプトを生成し直してください。`render certs` は CA を作り直すため不要です。

---

## `porkadot set-config` — kubeconfig 設定

kubectl の kubeconfig にクラスタ情報を設定します。コントロールプレーンエンドポイント（VIP）向けに切り替えます。

```
porkadot set-config
```
