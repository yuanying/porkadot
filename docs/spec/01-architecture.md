# アーキテクチャ

## 全体フロー

```
porkadot.yaml
     │
     ▼
porkadot render          ← 設定層 + アセット層
     │
     ├── 証明書生成 (PKI)
     ├── kubelet 設定ファイル生成
     ├── etcd マニフェスト生成
     ├── ブートストラップマニフェスト生成
     └── Kubernetes マニフェスト生成
     │
     ▼
assets/                  ← 生成されたファイル群
     │
     ▼
porkadot install         ← インストール層
     │
     ├── kubelet インストール（全ノード）
     ├── bootstrap フェーズ（一時的なコントロールプレーン）
     └── Kubernetes デプロイ（永続的なコントロールプレーン）
```

## 3 層アーキテクチャ

### 設定層 (`lib/porkadot/configs/`)

`porkadot.yaml` を読み込み、`lib/porkadot/default.yaml` とマージして型付きアクセサを提供する。各コンポーネントに対応したクラスが存在する。

| クラス | 対応セクション | 主な役割 |
|--------|---------------|---------|
| `Config` | ルート | YAML 読み込み・マージ・各設定クラスのファクトリ |
| `Configs::Kubernetes` | `kubernetes` | APIサーバー・スケジューラー・コントローラーマネージャー・ネットワーク設定 |
| `Configs::Etcd` | `etcd` + `nodes` | etcd クラスタメンバーの URL・証明書パス |
| `Configs::Kubelet` | `nodes` | ノードごとの kubelet 設定・接続情報 |
| `Configs::Bootstrap` | `bootstrap` | ブートストラップノードの特殊設定 |
| `Configs::Addons` | `addons` | アドオンのパス管理 |
| `Configs::Certs` | — | PKI パスの管理 |

`ConfigUtils` モジュールが各設定クラスに mixin され、`asset_path`・`secrets_path` ヘルパーと `method_missing` による生設定値へのドット記法アクセスを提供する。

### アセット層 (`lib/porkadot/assets/`)

設定値を元に ERB テンプレートをレンダリングして `assets/` ディレクトリに出力する。

| クラス | 出力先 | 主な出力物 |
|--------|--------|-----------|
| `Assets::Certs` | `assets/` (secrets) | 全 TLS 証明書・秘密鍵 |
| `Assets::KubeletDefault` | `assets/kubelet-default/` | 共通インストールスクリプト・CA 証明書 |
| `Assets::Kubelet` | `assets/kubelet/{node}/` | ノードごとの kubelet 設定・bootstrap kubeconfig |
| `Assets::EtcdList` | `assets/kubelet-default/addons/etcd/{node}/` | etcd 静的 Pod マニフェスト・環境変数 |
| `Assets::Bootstrap` | `assets/bootstrap/` | ブートストラップ用静的 Pod マニフェスト・スクリプト |
| `Assets::Kubernetes` | `assets/kubernetes/` | Kubernetes DaemonSet マニフェスト・アドオン・kubeconfig |

### インストール層 (`lib/porkadot/install/`)

SSHKit を使ってリモートノードに SSH 接続し、レンダリング済みアセットをデプロイする。

| クラス | 役割 |
|--------|------|
| `Install::KubeletList` | 全ノードへの kubelet デプロイ・containerd セットアップ・etcd バックアップ/リストア |
| `Install::Bootstrap` | ブートストラップノードへの一時コントロールプレーンデプロイ |
| `Install::Kubernetes` | kubectl/kustomize による Kubernetes マニフェスト適用 |

## Self-hosted アーキテクチャ（bootkube 方式）

porkadot は **self-hosted Kubernetes**（bootkube アーキテクチャ）を採用している。

通常の static Pod ベースのクラスタとは異なり、**コントロールプレーンが Kubernetes の DaemonSet として動作する**。

```
通常のクラスタ:
  kubelet → kube-apiserver (static pod)
           kube-controller-manager (static pod)
           kube-scheduler (static pod)

porkadot (self-hosted):
  kubelet → bootstrap apiserver (static pod) ─→ DaemonSet (kube-apiserver)
                                              → DaemonSet (kube-controller-manager)
                                              → DaemonSet (kube-scheduler)
                                              → DaemonSet (MetalLB, Flannel, ...)
```

**メリット:**
- `kubectl` でコントロールプレーンコンポーネントを管理・アップグレード可能
- MetalLB などのアドオンと同一ライフサイクルで管理できる

## ノードラベル定数

porkadot はノードの役割をラベルで識別する。

| 定数名 | ラベルキー | 用途 |
|--------|-----------|------|
| `K8S_MASTER_LABEL` | `k8s.unstable.cloud/master` | コントロールプレーンノードの識別 |
| `ETCD_MEMBER_LABEL` | `etcd.unstable.cloud/member` | etcd クラスタメンバーの識別（値はメンバー名） |
| `ETCD_ADDRESS_LABEL` | `etcd.unstable.cloud/address` | etcd advertise アドレスの上書き |
| `ETCD_LISTEN_ADDRESS_LABEL` | `etcd.unstable.cloud/listen-address` | etcd peer リッスンアドレスの上書き |
| `ETCD_LISTEN_CLIENT_ADDRESS_LABEL` | `etcd.unstable.cloud/listen-client-address` | etcd クライアントリッスンアドレスの上書き |
| `ETCD_LISTEN_PEER_ADDRESS_LABEL` | `etcd.unstable.cloud/listen-client-address` | etcd peer リッスンアドレスの上書き（現状実装値。`listen-peer-address` ではない） |

### ラベルの設定例

```yaml
nodes:
  192.168.22.111:
    labels:
      k8s.unstable.cloud/master: ""           # コントロールプレーンノード
      etcd.unstable.cloud/member: node91      # etcd メンバー名 = "node91"
    taints:
    - key: node-role.kubernetes.io/master
      effect: NoSchedule
```

`k8s.unstable.cloud/master` ラベルを持つノードが DaemonSet のノードセレクタに合致し、コントロールプレーンコンポーネント（kube-apiserver, kube-controller-manager, kube-scheduler）が配置される。
