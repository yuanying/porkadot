# 生成アセット

## ディレクトリ構成

`porkadot render` 実行後に生成されるアセットの構造です。デフォルトは `./assets/`（`local.assets_dir` で変更可能）。

```
assets/
├── kubelet-default/            # 全ノード共通の kubelet 関連ファイル
│   ├── ca.crt                  # Kubernetes CA 証明書
│   ├── install.sh              # kubelet インストールスクリプト
│   ├── install-deps.sh         # 依存関係インストールスクリプト
│   ├── install-pkgs.sh         # パッケージインストールスクリプト
│   ├── setup-node.sh           # ノード OS セットアップスクリプト
│   ├── setup-containerd.sh     # containerd セットアップスクリプト
│   └── addons/                 # アドオン（etcd 等）
│       └── etcd/
│           ├── {node1}/        # etcd メンバーごと
│           │   ├── etcd-server.yaml   # etcd 静的 Pod マニフェスト
│           │   ├── etcd.env           # etcd 環境変数
│           │   └── install.sh         # etcd インストールスクリプト
│           └── {node2}/
│
├── kubelet/                    # ノードごとの kubelet 設定
│   ├── {node1}/
│   │   ├── kubelet.service     # systemd サービスユニット
│   │   ├── config.yaml         # KubeletConfiguration
│   │   ├── bootstrap-kubelet.conf   # TLS ブートストラップ用 kubeconfig
│   │   ├── bootstrap.crt            # TLS ブートストラップ用クライアント証明書
│   │   ├── initiatorname.iscsi      # iSCSI 設定
│   │   └── metadata.json            # ノードメタデータ
│   └── {node2}/
│
├── bootstrap/                  # ブートストラップ用コントロールプレーン
│   ├── install.sh              # ブートストラップインストールスクリプト
│   ├── cleanup.sh              # ブートストラップクリーンアップスクリプト
│   ├── bootstrap/              # ブートストラップ設定ファイル
│   │   ├── kubeconfig-bootstrap.yaml  # ブートストラップ用 kubeconfig
│   │   └── kube-proxy-bootstrap.yaml  # kube-proxy ブートストラップ設定
│   └── manifests/              # ブートストラップ用静的 Pod マニフェスト
│       ├── kube-apiserver.bootstrap.yaml
│       ├── kube-controller-manager.bootstrap.yaml
│       ├── kube-scheduler.bootstrap.yaml
│       └── kube-proxy.bootstrap.yaml
│
└── kubernetes/                 # 永続的な Kubernetes コントロールプレーン
    ├── kustomization.yaml      # ルート kustomization（初回のみ生成）
    ├── install.sh              # マニフェスト適用スクリプト
    └── manifests/              # Kubernetes マニフェスト
        ├── kustomization.yaml
        ├── porkadot.yaml       # クラスタメタデータ
        ├── kubelet.yaml        # kubelet 設定テンプレート
        ├── kube-apiserver.yaml             # DaemonSet
        ├── kube-controller-manager.yaml    # DaemonSet
        ├── kube-scheduler.yaml             # DaemonSet
        ├── kube-proxy.yaml                 # DaemonSet
        ├── crds/
        │   └── metallb/
        │       └── crds.yaml               # MetalLB CRD
        └── addons/
            ├── kustomization.yaml
            ├── flannel/
            │   ├── flannel.yaml
            │   └── kustomization.yaml
            ├── coredns/
            │   ├── coredns.yaml
            │   ├── dns-horizontal-autoscaler.yaml
            │   └── kustomization.yaml
            ├── metallb/
            │   ├── 000-metallb.yaml       # Namespace/RBAC 等
            │   ├── metallb.yaml           # Deployment/DaemonSet
            │   ├── metallb.config.yaml    # IPAddressPool/L2Advertisement
            │   └── kustomization.yaml
            ├── kubelet-serving-cert-approver/
            │   ├── src.yaml
            │   └── kustomization.yaml
            └── storage-version-migrator/
                ├── storage-version-migrator.yaml
                └── kustomization.yaml
```

## secrets/ ディレクトリ

TLS 証明書・秘密鍵・kubeconfig 等の秘密情報は `local.assets_dir/secrets/` に格納されます。デフォルトでは `./assets/secrets/` です。

```
assets/secrets/
├── certs/
│   ├── kubernetes/
│   │   ├── ca.key / ca.crt
│   │   ├── apiserver.key / apiserver.crt
│   │   ├── kubelet-client.key / kubelet-client.crt
│   │   ├── admin.key / admin.crt
│   │   ├── sa.key / sa.pub
│   │   └── front-proxy/
│   │       ├── ca.key / ca.crt
│   │       └── client.key / client.crt
│   └── etcd/
│       ├── ca.key / ca.crt
│       ├── client.key / client.crt
│       └── {node}/
│           └── etcd.key / etcd.crt
├── kubelet-default/
│   └── addons/etcd/{node}/
│       └── ca.crt
├── kubelet/
│   └── {node}/
│       └── bootstrap.key
├── bootstrap/
│   ├── bootstrap/
│   │   └── kubeconfig-bootstrap.yaml
│   └── secrets/               # 全証明書のコピー（bootstrap node に転送）
└── kubernetes/
    ├── kubeconfig.yaml        # admin kubeconfig
    └── manifests/
        ├── kube-apiserver.secrets.yaml
        ├── kube-controller-manager.secrets.yaml
        └── install.secrets.sh
```

## 主要ファイルの説明

### `kubelet-default/install.sh`

kubelet バイナリ・設定・証明書・systemd サービスをインストールします。

実行内容:
1. 必要なディレクトリを作成（`/etc/kubernetes/pki/`, `/var/lib/kubelet/` 等）
2. bootstrap kubeconfig と PKI 証明書を `/etc/kubernetes/` にコピー
3. kubelet 設定を `/var/lib/kubelet/config.yaml` にコピー
4. systemd サービスユニットをインストール
5. アドオンインストールスクリプト（`setup-node.sh`）を実行
6. systemd デーモンリロード → kubelet サービス有効化・再起動

### `kubelet-default/setup-containerd.sh`

containerd コンテナランタイムを Kubernetes 向けに設定します。

実行内容:
1. デフォルト設定を生成（`containerd config default`）
2. systemd cgroup ドライバーを有効化（`SystemdCgroup = true`）
3. containerd サービスを再起動

### `kubelet-default/setup-node.sh`

ノードの OS 設定とアドオンインストールを行います。アドオンディレクトリ内の `install.sh` を順次実行します。

### `bootstrap/install.sh`

ブートストラップ用の静的 Pod マニフェストと秘密情報をブートストラップノードに配置します。

実行内容:
1. ブートストラップ設定ファイルを `/etc/kubernetes/bootstrap/` にコピー
2. ブートストラップ用マニフェストを `/etc/kubernetes/manifests/` にコピー

### `bootstrap/cleanup.sh`

ブートストラップ静的 Pod を削除します。

実行内容:
1. `/etc/kubernetes/bootstrap/` ディレクトリを削除
2. `/etc/kubernetes/manifests/*.bootstrap.yaml` を削除

### `kubernetes/install.sh`

kubectl/kustomize を使って Kubernetes マニフェストを適用します。

実行内容:
1. CRD を適用（サーバーサイドコンフリクト解決）
2. CRD が確立するまで待機（最大 60 秒）
3. kustomize で全マニフェストを適用（プルーニング付き）
   - `kubernetes.unstable.cloud/installed-by=porkadot` ラベルで管理リソースを追跡
   - `KUBE_TARGET` 環境変数が設定されている場合は特定コンポーネントのみ適用

### `kubelet/{node}/kubelet.service`

kubelet の systemd サービスユニットです。

主要設定:
- containerd ソケット（`unix:///var/run/containerd/containerd.sock`）を使用
- TLS ブートストラップ用に `bootstrap-kubelet.conf` を指定
- 証明書ローテーション後は `kubelet.conf` を使用
- 失敗時は 10 秒後に自動再起動

### `kubelet/{node}/bootstrap-kubelet.conf`

kubelet の初回起動時に使用する kubeconfig です。

- サーバー: `{control_plane_endpoint}`（通常は VIP）
- クライアント証明書: `/etc/kubernetes/pki/bootstrap.{crt,key}`（生成時は証明書が `assets/kubelet/{node}/bootstrap.crt`、秘密鍵が `assets/secrets/kubelet/{node}/bootstrap.key`）
- CA データ: Kubernetes CA 証明書（Base64 エンコード埋め込み）

### `bootstrap/manifests/kube-apiserver.bootstrap.yaml`

ブートストラップ用 kube-apiserver の静的 Pod マニフェストです。

主要設定:
- `hostNetwork: true`
- バインドアドレス: `127.0.0.1`
- 秘密情報マウント: `/etc/kubernetes/bootstrap/secrets/`
- Priority Class: `system-cluster-critical`
- CPU リクエスト: `250m`
- Liveness/Readiness/Startup プローブあり

### `kubernetes/manifests/kube-apiserver.yaml`

永続的な kube-apiserver の DaemonSet マニフェストです。

主要設定:
- `hostNetwork: true`
- ノードセレクタ: `k8s.unstable.cloud/master: ""`
- マスターノードのテイント（`NoSchedule`）を許容
- Priority Class: `system-cluster-critical`
- CPU リクエスト: `250m`
- Liveness/Readiness/Startup プローブあり
- checkpoint アノテーション付き（bootkube 互換）
