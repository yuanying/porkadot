# アドオン仕様・etcd 操作

## アドオン概要

porkadot は `addons.enabled` リストに基づいてアドオンをデプロイします。各アドオンは kustomize で管理されます。

デフォルトで有効なアドオン:
```yaml
addons:
  enabled: [flannel, coredns, metallb, kubelet-serving-cert-approver, storage-version-migrator]
```

---

## アドオン一覧

### flannel（CNI ネットワーク）

Pod 間のネットワーキングを提供します。

| 設定キー | デフォルト | 説明 |
|---------|-----------|------|
| `backend` | `vxlan` | ネットワークバックエンド（`vxlan` / `host-gw`） |
| `plugin_image_repository` | `flannel/flannel-cni-plugin` | CNI プラグインイメージ |
| `plugin_image_tag` | `v1.4.1-flannel1` | CNI プラグインイメージタグ |
| `daemon_image_repository` | `flannel/flannel` | Flannel デーモンイメージ |
| `daemon_image_tag` | `v0.25.1` | Flannel デーモンイメージタグ |
| `resources.requests.cpu` | `100m` | CPU リクエスト |
| `resources.requests.memory` | `50Mi` | メモリリクエスト |
| `resources.limits.cpu` | `100m` | CPU リミット |
| `resources.limits.memory` | `50Mi` | メモリリミット |

設定例（`host-gw` バックエンド使用）:
```yaml
addons:
  flannel:
    backend: host-gw
```

Pod CIDR は `kubernetes.networking.pod_subnet` から自動設定されます。

---

### coredns（クラスター DNS）

Kubernetes クラスター内の DNS サービスを提供します。

追加設定なし（デフォルト値のみ）。

CoreDNS の IP アドレスは `networking.service_subnet` の 10 番目のアドレスが使用されます（例: `10.254.0.0/24` の場合は `10.254.0.10`）。

---

### metallb（ロードバランサー）

LoadBalancer タイプの Service に外部 IP アドレスを割り当てます。ブートストラップフェーズでコントロールプレーン VIP の確立にも使用されます。

| 設定キー | デフォルト | 説明 |
|---------|-----------|------|
| `config` | デフォルトプール設定 | MetalLB 設定（YAML 文字列） |

`config` には MetalLB の `IPAddressPool` と `L2Advertisement` リソースを記述します。

設定例:
```yaml
addons:
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
        - 2405:6581:8580:301:face:b00c::/96
      ---
      apiVersion: metallb.io/v1beta1
      kind: L2Advertisement
      metadata:
        name: system
        namespace: metallb-system
```

MetalLB は CRD を使用するため、`assets/kubernetes/manifests/crds/metallb/crds.yaml` として CRD が出力されます。インストール時は CRD が先に適用されます。

---

### kubelet-serving-cert-approver（証明書自動承認）

kubelet のサービング証明書 CSR を自動承認します。`serverTLSBootstrap: true` が有効な環境で必要です。

追加設定なし。

`kubelet-rubber-stamp` の後継として推奨されるアドオンです。

---

### storage-version-migrator（ストレージバージョン移行）

Kubernetes API リソースのストレージバージョン移行を管理します。Kubernetes のアップグレード時に使用されます。

追加設定なし。

---

### kubelet-rubber-stamp（証明書自動承認・旧）

`kubelet-serving-cert-approver` の旧バージョン相当です。新規インストールでは `kubelet-serving-cert-approver` を使用してください。

追加設定なし。デフォルトでは無効（`addons.enabled` に含まれていない）。

---

## etcd 操作

etcd の管理操作は `porkadot etcd` サブコマンドで行います。

### etcd の仕組み

porkadot では etcd は各マスターノード上で **静的 Pod** として動作します。`etcd-server.yaml` が `/etc/kubernetes/manifests/` に存在するときに kubelet が起動します。

### バックアップ

```bash
# デフォルトの ./backup ディレクトリにバックアップ
porkadot etcd backup

# バックアップ先を指定
porkadot etcd backup --path /mnt/backup

# 特定のノードでバックアップ
porkadot etcd backup --node 192.168.22.111
```

出力ファイル: `{path}/etcd-{DateTime.now.to_s}.db`

etcdctl のオプション（証明書パス等）は設定から自動的に構築されます。

### リストア

```bash
# 最新バックアップからリストア
porkadot etcd restore

# バックアップ先を指定
porkadot etcd restore --path /mnt/backup
```

リストア手順（内部処理）:
1. etcd を停止（全メンバーノード）
2. 指定ディレクトリ内の最新バックアップファイルを選択
3. etcd データをリストア（全メンバーノード）
4. etcd を起動（全メンバーノード）

バックアップファイルが見つからない場合はエラーで終了します。

### 手動での etcd 停止・起動

```bash
# etcd を停止
porkadot etcd stop

# etcd を起動
porkadot etcd start

# 特定ノードのみ操作
porkadot etcd stop --node 192.168.22.111
porkadot etcd start --node 192.168.22.111
```

etcd の停止/起動は `etcd-server.yaml` を `/etc/kubernetes/manifests/` に対して移動・退避することで行われます（kubelet が静的 Pod として管理するため）。

### etcd 接続設定

etcdctl コマンドは以下の証明書ファイルを使用します:

| オプション | ファイル |
|-----------|---------|
| `--cacert` | `/etc/etcd/pki/ca.crt` |
| `--cert` | `/etc/etcd/pki/etcd.crt` |
| `--key` | `/etc/etcd/pki/etcd.key` |
| `--endpoints` | `https://127.0.0.1:2379` |

### etcd メンバーの URL 構成

各 etcd メンバーは以下のポートで通信します。

| ポート | 用途 |
|--------|------|
| `2379` | クライアント通信（kube-apiserver との通信） |
| `2380` | Peer 間通信（etcd メンバー間の同期） |
| `2381` | メトリクス（HTTP、TLS なし） |

メンバーのアドレスは `etcd.unstable.cloud/member` ラベルの値（メンバー名）から決定されます。`etcd.unstable.cloud/address` ラベルで advertise アドレスを明示的に上書きできます。
