# 設定ファイル仕様

## 概要

`porkadot.yaml`（デフォルトパス）がクラスタ設定ファイルです。ユーザーが記述した値と `lib/porkadot/default.yaml` のデフォルト値が再帰マージされます。

## トップレベルセクション

```yaml
nodes:        # ノード定義（必須）
bootstrap:    # ブートストラップ設定
kubernetes:   # Kubernetes クラスタ設定
etcd:         # etcd 設定
addons:       # アドオン設定
connection:   # SSH 接続デフォルト
local:        # ローカル設定
```

---

## `nodes` セクション

クラスタを構成する全ノードを定義します。キーはノード名（通常は IP アドレスまたはホスト名）です。

```yaml
nodes:
  <node-name>:
    labels:           # ノードラベル（役割の識別に使用）
    taints:           # ノードテイント
    annotations:      # ノードアノテーション
    connection:       # このノード固有の SSH 接続設定（グローバル connection をオーバーライド）
```

### ラベルによるノード役割の指定

| ラベル | 値 | 意味 |
|--------|-----|------|
| `k8s.unstable.cloud/master` | `""` | コントロールプレーンノード |
| `etcd.unstable.cloud/member` | メンバー名（例: `node91`） | etcd クラスタメンバー |
| `etcd.unstable.cloud/address` | IP/ホスト名 | etcd advertise アドレス上書き |
| `etcd.unstable.cloud/listen-address` | IP/`0.0.0.0` | etcd peer リッスンアドレス上書き |
| `etcd.unstable.cloud/listen-client-address` | IP/`0.0.0.0` | etcd クライアントリッスンアドレス上書き |

### ノード設定例

```yaml
nodes:
  192.168.22.111:
    labels:
      k8s.unstable.cloud/master: ""
      etcd.unstable.cloud/member: node91
    taints:
    - key: node-role.kubernetes.io/master
      effect: NoSchedule

  192.168.22.121:       # ワーカーノード（ラベルなし）
  192.168.22.122:
```

---

## `bootstrap` セクション

初回デプロイ時に使用する一時的なコントロールプレーン（ブートストラップ）の設定です。

```yaml
bootstrap:
  node:
    hostname: <node-hostname>   # ブートストラップノードのホスト名/IP
```

ブートストラップノードには一時的な apiserver（`127.0.0.1:6443`）が static Pod として起動します。ブートストラップ完了後は cleanup コマンドで削除されます。

---

## `kubernetes` セクション

Kubernetes クラスタ全体の設定です。

### 基本設定

| キー | デフォルト | 説明 |
|------|-----------|------|
| `cluster_name` | `porkadot` | クラスタ名 |
| `control_plane_endpoint` | — | コントロールプレーンエンドポイント（例: `192.168.23.101:6443`）|
| `kubernetes_version` | `v1.29.8` | Kubernetes バージョン |
| `crictl_version` | `v1.28.0` | crictl バージョン |
| `image_repository` | `registry.k8s.io` | コンテナイメージリポジトリ |

### `kubernetes.networking`

| キー | デフォルト | 説明 |
|------|-----------|------|
| `cni_version` | `v1.4.1` | CNI プラグインバージョン |
| `service_subnet` | `10.254.0.0/24` | Service CIDR（デュアルスタック時はカンマ区切り） |
| `pod_subnet` | `10.244.0.0/16` | Pod CIDR（デュアルスタック時はカンマ区切り） |
| `dns_domain` | `cluster.local` | クラスタ DNS ドメイン |
| `additional_domains` | `[]` | 追加 DNS ドメイン |

デュアルスタックの例:
```yaml
networking:
  service_subnet: "10.252.0.0/24,fd90:cca6:9762:96::/108"
  pod_subnet: "10.242.0.0/16,fd49:d591:8c7e::/48"
```

### `kubernetes.apiserver`

| キー | デフォルト | 説明 |
|------|-----------|------|
| `bind_port` | `6443` | API サーバーがリッスンするポート |
| `extra_args` | — | 追加 CLI フラグ |
| `log_level` | — | ログレベル |

### `kubernetes.controller_manager`

| キー | デフォルト | 説明 |
|------|-----------|------|
| `extra_args` | — | 追加 CLI フラグ |
| `log_level` | — | ログレベル |

### `kubernetes.scheduler`

| キー | デフォルト | 説明 |
|------|-----------|------|
| `extra_args` | — | 追加 CLI フラグ |
| `log_level` | — | ログレベル |

### `kubernetes.proxy`

kube-proxy の設定を `KubeProxyConfiguration` 形式で記述します。

| キー | デフォルト | 説明 |
|------|-----------|------|
| `config` | — | KubeProxyConfiguration オブジェクト |
| `config.mode` | `iptables` | プロキシモード（`iptables` または `ipvs`） |
| `config.clusterCIDR` | pod_subnet から自動設定 | Pod CIDR |

デフォルト設定には以下が含まれます（抜粋）:
- `bindAddress: 0.0.0.0`
- `healthzBindAddress: 0.0.0.0:10256`
- `metricsBindAddress: 0.0.0.0:10249`
- `conntrack.maxPerCore: 32768`
- `conntrack.tcpEstablishedTimeout: 24h0m0s`

### `kubernetes.kubelet`

全ノード共通の kubelet 設定を `KubeletConfiguration` 形式で記述します。

| キー | デフォルト | 説明 |
|------|-----------|------|
| `config` | — | KubeletConfiguration オブジェクト |

主要なデフォルト値（抜粋）:

| 設定 | デフォルト |
|------|-----------|
| `cgroupDriver` | `systemd` |
| `rotateCertificates` | `true` |
| `serverTLSBootstrap` | `true` |
| `authentication.anonymous.enabled` | `false` |
| `authentication.webhook.enabled` | `true` |
| `authorization.mode` | `Webhook` |
| `staticPodPath` | `/etc/kubernetes/manifests` |
| `resolvConf` | `/run/systemd/resolve/resolv.conf` |

---

## `etcd` セクション

etcd クラスタの設定です。

| キー | デフォルト | 説明 |
|------|-----------|------|
| `image_repository` | `registry.k8s.io/etcd` | etcd イメージリポジトリ |
| `image_tag` | `3.5.12-0` | etcd イメージタグ |
| `extra_env` | `[]` | 追加環境変数（例: ARM64 サポート用） |

追加環境変数の例（ARM64 向け）:
```yaml
etcd:
  image_tag: v3.4.3-arm64
  extra_env:
  - name: ETCD_UNSUPPORTED_ARCH
    value: arm64
```

---

## `addons` セクション

Kubernetes アドオンの設定です。

### `addons.enabled`

有効にするアドオンのリストです。

デフォルト:
```yaml
addons:
  enabled: [flannel, coredns, metallb, kubelet-serving-cert-approver, storage-version-migrator]
```

### アドオン別設定

#### `addons.flannel`

| キー | デフォルト | 説明 |
|------|-----------|------|
| `backend` | `vxlan` | ネットワークバックエンド（`vxlan` または `host-gw`） |
| `plugin_image_repository` | `flannel/flannel-cni-plugin` | CNI プラグインイメージ |
| `plugin_image_tag` | `v1.4.1-flannel1` | CNI プラグインイメージタグ |
| `daemon_image_repository` | `flannel/flannel` | Flannel デーモンイメージ |
| `daemon_image_tag` | `v0.25.1` | Flannel デーモンイメージタグ |
| `resources.requests.cpu` | `100m` | CPU リクエスト |
| `resources.requests.memory` | `50Mi` | メモリリクエスト |
| `resources.limits.cpu` | `100m` | CPU リミット |
| `resources.limits.memory` | `50Mi` | メモリリミット |

#### `addons.coredns`

追加設定なし（デフォルト値のみ）。

#### `addons.metallb`

| キー | デフォルト | 説明 |
|------|-----------|------|
| `config` | デフォルトプール設定 | MetalLB の IPAddressPool / L2Advertisement 設定（YAML 文字列） |

デフォルト設定:
```yaml
metallb:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 192.168.1.240-192.168.1.250
```

MetalLB v1beta1 CRD 形式での設定例:
```yaml
metallb:
  config: |
    ---
    apiVersion: metallb.io/v1beta1
    kind: IPAddressPool
    metadata:
      name: first-pool
      namespace: metallb-system
    spec:
      addresses:
      - 192.168.23.0/24
    ---
    apiVersion: metallb.io/v1beta1
    kind: L2Advertisement
    metadata:
      name: system
      namespace: metallb-system
```

#### `addons.kubelet-serving-cert-approver`

追加設定なし。kubelet サービング証明書を自動承認する。

#### `addons.storage-version-migrator`

追加設定なし。Kubernetes API ストレージバージョンの移行を行う。

#### `addons.kubelet-rubber-stamp`（非推奨）

追加設定なし。`kubelet-serving-cert-approver` の旧バージョン相当。

---

## `connection` セクション

全ノード共通の SSH 接続設定です。ノードごとに `nodes.<name>.connection` でオーバーライドできます。

| キー | デフォルト | 説明 |
|------|-----------|------|
| `user` | `ubuntu` | SSH ユーザー名 |
| `port` | `22` | SSH ポート |
| `keys` | `["~/.ssh/id_rsa", "~/.ssh/id_dsa"]` | SSH 秘密鍵のパス |

---

## `local` セクション

porkadot を実行するローカルマシンの設定です。

| キー | デフォルト | 説明 |
|------|-----------|------|
| `assets_dir` | `./assets` | 生成アセットの出力ディレクトリ |
