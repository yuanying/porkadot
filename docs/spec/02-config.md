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
| `kubernetes_version` | `v1.36.5` | Kubernetes バージョン |
| `crictl_version` | `v1.36.0` | crictl バージョン |
| `image_repository` | `registry.k8s.io` | コンテナイメージリポジトリ |

### `kubernetes.networking`

| キー | デフォルト | 説明 |
|------|-----------|------|
| `cni_version` | `v1.9.1` | 標準の CNI plugins（containernetworking/plugins）のバージョン。`install kubelet` が `/opt/cni/bin` に置く（[07-addons.md](07-addons.md#cni-plugins-の持ち主)） |
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
| `config.mode` | `iptables` | プロキシモード（`iptables` または `ipvs`）。`ipvs` は Kubernetes 1.35 で非推奨になった |
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

`failCgroupV1` は設定しない。Kubernetes 1.35 から kubelet の既定値が `true` になり、cgroup v1 のノードでは kubelet が起動しない。ノードは cgroup v2 で動かす（`stat -fc %T /sys/fs/cgroup` が `cgroup2fs`）。cgroup v1 のまま動かす必要があるときだけ、`config` に `failCgroupV1: false` を書く。

---

## `etcd` セクション

etcd クラスタの設定です。

| キー | デフォルト | 説明 |
|------|-----------|------|
| `image_repository` | `registry.k8s.io/etcd` | etcd イメージリポジトリ |
| `image_tag` | `3.6.15-0` | etcd イメージタグ。etcdctl・etcdutl の版にもなる（`-0` などの接尾辞を除く） |
| `extra_env` | `[]` | 追加環境変数（例: ARM64 サポート用） |

追加環境変数の例（ARM64 向け）:
```yaml
etcd:
  image_tag: v3.4.3-arm64
  extra_env:
  - name: ETCD_UNSUPPORTED_ARCH
    value: arm64
```

etcd の一部のフラグは 3.6 で名前が変わり、3.7 で古い名前が消えました。新しい名前は 3.5 では使えないので、`etcd-server.yaml` は `image_tag` の major.minor で出し分けます。major.minor が読めないタグは 3.6 以上として扱います。

| 3.5 以前 | 3.6 以上 |
|---------|---------|
| `--experimental-initial-corrupt-check=true` | `--feature-gates=InitialCorruptCheck=true` |
| `--experimental-watch-progress-notify-interval=5s` | `--watch-progress-notify-interval=5s` |

---

## `addons` セクション

Kubernetes アドオンの設定です。

### `addons.enabled`

有効にするアドオンのリストです。

デフォルト:
```yaml
addons:
  enabled: [flannel, coredns, metallb, kubelet-serving-cert-approver]
```

未知のアドオン名や、削除済みのアドオン（`storage-version-migrator`）を含めると、設定の検証エラーになります。削除済みのアドオンの扱いは [07-addons.md](07-addons.md) の「削除済みのアドオン」を参照してください。

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

#### `addons.cnidaria`

flannel の代わりに使える CNI（opt-in）。使うときは `addons.enabled` の `flannel` を `cnidaria` に置き換える。flannel と同時に有効にした設定は検証エラーになる。

| キー | デフォルト | 説明 |
|------|-----------|------|
| `image_repository` | `ghcr.io/yuanying/cnidaria-cni` | cnidaria イメージ |
| `image_tag` | `v0.1.1` | cnidaria イメージタグ |
| `network_name` | `cnidaria` | conflist のネットワーク名（`--network-name`）。host-local の IP 割り当ては `/var/lib/cni/networks/<name>` に保存される |
| `resources.requests.cpu` | `50m` | CPU リクエスト |
| `resources.requests.memory` | `64Mi` | メモリリクエスト |
| `resources.limits.memory` | `256Mi` | メモリリミット |

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

kubelet サービング証明書を自動承認する。

| キー | デフォルト | 説明 |
|------|-----------|------|
| `image_repository` | `ghcr.io/alex1989hu/kubelet-serving-cert-approver` | approver イメージ |
| `image_tag` | `0.12.1` | approver イメージタグ（上流のリリース `v0.12.1` に当たる。イメージのタグに `v` は付かない） |

#### `addons.kubelet-rubber-stamp`（非推奨）

追加設定なし。`kubelet-serving-cert-approver` の旧バージョン相当。

---

## `connection` セクション

全ノード共通の SSH 接続設定です。ノードごとに `nodes.<name>.connection` でオーバーライドできます。

| キー | デフォルト | 説明 |
|------|-----------|------|
| `user` | `ubuntu` | SSH ユーザー名 |
| `port` | `22` | SSH ポート |
| `keys` | なし | SSH 秘密鍵のパス（例: `["~/.ssh/id_ed25519"]`） |

`keys` を書かなければ、net-ssh が OpenSSH と同じように鍵を選ぶ。ssh-agent の鍵と、`~/.ssh/config` の `IdentityFile`（無ければ `~/.ssh/id_ed25519`・`id_rsa`・`id_dsa`・`id_ecdsa`）を使う。`keys` を書くとその鍵ファイルだけを読み、`IdentityFile` と既定の鍵ファイルは使わない（ssh-agent の鍵は使う）。

ssh-agent が使えない環境でも、鍵ファイルを直接読んで入れる。ed25519 の鍵も読める（`ed25519`・`bcrypt_pbkdf` の gem）。パスフレーズ付きの鍵は、ssh-agent が無いと入力を求められる。

ホスト鍵は `~/.ssh/known_hosts`（`UserKnownHostsFile`）と `/etc/ssh/ssh_known_hosts` で確かめる。hashed の行（`HashKnownHosts yes`）も、同じホストの複数の行（rsa・ecdsa・ed25519）も読む。

---

## `local` セクション

porkadot を実行するローカルマシンの設定です。

| キー | デフォルト | 説明 |
|------|-----------|------|
| `assets_dir` | `./assets` | 生成アセットの出力ディレクトリ |
| `sops.enabled` | `false` | secret を sops で暗号化して書き込む |
| `sops.config` | なし | sops の設定ファイル（`.sops.yaml`）のパス。相対パスは `porkadot.yaml` のあるディレクトリ基準 |

`assets_dir` の相対パスは、porkadot を実行したディレクトリを基準に解決されます。

### `local.sops`

`sops.enabled: true` にすると、porkadot が secret として出力するファイル（証明書・秘密鍵・kubeconfig・secret マニフェスト等）を sops で暗号化して書き込みます。暗号化した assets は git で管理できます。

- sops は `porkadot.yaml` のあるディレクトリで実行され、通常どおり `.sops.yaml` を探します。`sops.config` を指定するとそのファイルを使います。
- 鍵（age recipients 等）は `.sops.yaml` の `creation_rules` で指定します。`path_regex` は `.sops.yaml` のあるディレクトリからの相対パス（例: `assets/.*`）と照合されます。
- 復号に必要な鍵（age なら `SOPS_AGE_KEY_FILE` など）は、render・install・set-config を実行する環境で sops が使えるように設定してください。
- 無効のときも、すでに暗号化されたファイルは読み込み時に復号されます。

```yaml
local:
  assets_dir: ./assets
  sops:
    enabled: true
```

