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
│   └── setup-containerd.sh     # containerd セットアップスクリプト
│
├── kubelet/                    # ノードごとの kubelet 設定
│   ├── {node1}/
│   │   ├── kubelet.service     # systemd サービスユニット
│   │   ├── config.yaml         # KubeletConfiguration
│   │   ├── bootstrap-kubelet.conf   # TLS ブートストラップ用 kubeconfig
│   │   ├── bootstrap.crt            # TLS ブートストラップ用クライアント証明書
│   │   ├── initiatorname.iscsi      # iSCSI 設定
│   │   ├── metadata.json            # ノードメタデータ
│   │   └── addons/etcd/             # etcd メンバーのみ
│   │       ├── etcd-server.yaml     # etcd 静的 Pod マニフェスト
│   │       ├── etcd.env             # etcd 環境変数
│   │       └── install.sh           # etcd インストールスクリプト
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
        │   ├── cnidaria/
        │   │   └── crds.yaml               # cnidaria NodeNetworkPolicy CRD（cnidaria 有効時）
        │   └── metallb/
        │       └── crds.yaml               # MetalLB CRD
        └── addons/
            ├── kustomization.yaml
            ├── flannel/                   # flannel 有効時
            │   ├── flannel.yaml
            │   └── kustomization.yaml
            ├── cnidaria/                  # cnidaria 有効時（flannel と排他）
            │   ├── cnidaria.yaml
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
            └── kubelet-serving-cert-approver/
                ├── src.yaml
                └── kustomization.yaml
```

## secret ファイル

TLS 証明書・秘密鍵・kubeconfig 等の秘密情報（secret）も、通常の asset と同じツリーに出力されます。以前の porkadot は `assets/secrets/` に分けて出力していました。そのツリーが残っている場合は `porkadot migrate-secrets` で移行します（[CLI](03-cli.md#porkadot-migrate-secrets--secret-の移行)）。

secret として扱うファイルは次のとおりです。ローカルではモード 0600 で書き込まれ、`local.sops.enabled: true` のときは sops で暗号化されます（[設定](02-config.md#local-セクション)）。

```
assets/
├── certs/                       # PKI（render certs が生成。不足分は render bootstrap も生成）
│   ├── kubernetes/              # Kubernetes CA・apiserver・kubelet-client・admin・SA 鍵・front-proxy
│   └── etcd/                    # etcd CA・etcd-client
├── kubelet/
│   └── {node}/
│       ├── bootstrap.key        # TLS ブートストラップ用秘密鍵
│       └── addons/etcd/         # etcd メンバーのみ
│           ├── ca.crt
│           ├── etcd.crt
│           └── etcd.key
├── bootstrap/
│   ├── kubelet/bootstrap.key
│   └── bootstrap/secrets/       # certs/ の必要分のコピー（bootstrap node に転送）
└── kubernetes/
    ├── kubeconfig.yaml          # admin kubeconfig
    ├── install.secrets.sh       # secret マニフェストの適用スクリプト
    └── manifests/
        ├── kube-apiserver.secrets.yaml
        └── kube-controller-manager.secrets.yaml
```

### sops による暗号化

`local.sops.enabled: true` のとき、上の secret は sops の binary 形式で暗号化されます。

- ファイル名は変わりません。中身は `data` と `sops` をキーに持つ JSON になります。YAML の secret も同じ形式です（sops の YAML 形式は復号すると元のバイト列に戻らないため）。
- 中身にトップレベルの `sops` キーがあるファイルを暗号化済みとみなします。暗号化済みのファイルは、`local.sops.enabled` の値にかかわらず読み込み時に復号されます。
- 再 render では既存ファイルを復号して比較し、内容が同じなら書き込みません。暗号文が無意味に変わらないため、assets を git で管理できます。
- install 時は各ファイルをメモリ上で復号して upload します。ノードには暗号化前と同じ内容が届きます。平文はローカルディスクに書かれません。

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
   - prune の対象は `--prune-allowlist` で指定した種類に限る（`Kubernetes#prune_allowlist`）。**Namespace は prune しない**。Namespace を消すと中のリソースもすべて消え、`kube-system` のように複数のアドオンが共有する Namespace もあるため。アドオンを無効にしても、そのアドオンが作った Namespace はクラスタに残る（[07-addons.md](07-addons.md) の「アドオンを無効にしたとき」）
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
- クライアント証明書: `/etc/kubernetes/pki/bootstrap.{crt,key}`（生成時は `assets/kubelet/{node}/bootstrap.{crt,key}`）
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
