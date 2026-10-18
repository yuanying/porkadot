# デプロイフロー

## 全体フロー

```
1. porkadot render    ← アセット生成（ローカル）
2. porkadot setup-node          ← ノード OS セットアップ（SSH）
3. porkadot setup-containerd    ← containerd セットアップ（SSH）
4. porkadot install kubelet     ← kubelet インストール（全ノード・SSH）
5. porkadot install bootstrap   ← ブートストラップ（SSH）
   5a. install bootstrap node       ← 一時コントロールプレーン起動
   5b. install bootstrap kubernetes ← DaemonSet/アドオンデプロイ
   5c. install bootstrap cleanup    ← 一時コントロールプレーン削除
6. porkadot install kubelet     ← ブートストラップノードの kubelet 設定復旧
```

---

## `porkadot render` の詳細

`render all` は以下の順で実行されます。

### 1. `render certs`

PKI 全体を生成します。証明書は `assets/certs/` サブディレクトリに格納されます。`local.sops.enabled: true` なら秘密鍵・証明書は sops で暗号化して書き込まれます。

- Kubernetes PKI（CA、apiserver、kubelet クライアント、admin、service account）
- etcd PKI（CA、各メンバー証明書）
- front-proxy PKI（CA、クライアント証明書）

既存の秘密鍵ファイルは再利用されます。`render certs` は証明書生成時に refresh=true を渡すため、証明書ファイル自体は再発行されます。

### 2. `render kubelet`

全ノードの kubelet 設定を生成します。

- 共通スクリプト（`install.sh`, `setup-containerd.sh` 等）
- Kubernetes CA 証明書（`ca.crt`）
- ノードごと: `kubelet.service`、`config.yaml`、`bootstrap-kubelet.conf`、ブートストラップ証明書（秘密鍵 + 自己署名証明書）

### 3. `render etcd`

etcd メンバーの設定を生成します。

- etcd 静的 Pod マニフェスト（`etcd-server.yaml`）
- etcd 環境変数ファイル（`etcd.env`）
- etcd TLS 証明書・秘密鍵
- インストールスクリプト

### 4. `render bootstrap`

ブートストラップ用の一時コントロールプレーンマニフェストを生成します。

- ブートストラップ用 kube-apiserver（`127.0.0.1` バインド）
- ブートストラップ用 kube-controller-manager
- ブートストラップ用 kube-scheduler
- ブートストラップ用 kube-proxy
- `kubeconfig-bootstrap.yaml`（`127.0.0.1:6443` 向け）
- `install.sh` / `cleanup.sh`
- `bootstrap/secrets/`（ブートストラップ用コントロールプレーンが読む証明書・鍵のコピー）

secrets にコピーする証明書・鍵は一覧で決まっています（etcd の CA・etcd-client、Kubernetes の CA・apiserver・kubelet-client・admin・SA 鍵、front-proxy の CA・client）。`assets/certs/` に無いものはその場で生成し、既にあるものは作り直さずに使います。そのため `render certs` を先に実行していなくても、`render bootstrap` だけで secrets が揃います。

### 5. `render kubernetes`

永続的なコントロールプレーンのマニフェストを生成します。

- kube-apiserver DaemonSet マニフェスト
- kube-controller-manager DaemonSet マニフェスト
- kube-scheduler DaemonSet マニフェスト
- kube-proxy DaemonSet マニフェスト
- 各アドオンマニフェスト
- admin kubeconfig（`kubeconfig.yaml`）
- `install.sh` / `install.secrets.sh`
- kustomization.yaml

---

## `porkadot install` の詳細

### ステップ 1: kubelet インストール（全ノード）

`porkadot install kubelet` がすべてのノードに対して以下を実行します。

assets は、ノードの一時ディレクトリ（`./kube_temp/<group>`）へファイルごとに upload されます。kubelet では `kubelet-default/` に `kubelet/{node}/` を重ねて同じディレクトリに置きます。sops で暗号化された secret は、upload 時にメモリ上で復号されます。

1. `install-deps.sh` — kubectl・kubelet・etcdctl・crictl と CNI plugins を設定の版にそろえる（下記）
2. `install-pkgs.sh` — パッケージをインストール
3. `install.sh` — kubelet バイナリ・設定・証明書・systemd サービスをインストール

`install-deps.sh` は毎回実行され、コンポーネントごとに次のように振る舞います。

- kubectl・kubelet・etcdctl・crictl は `/opt/bin/<名前>-<版>` に置き、`/opt/bin/<名前>` の symlink をその版に向けます。版は `kubernetes.kubernetes_version`、`etcd.image_tag`（`-0` などの接尾辞を除く）、`kubernetes.crictl_version` から決まります。
  - 目標の版の実体がノードに無いときだけダウンロードします。前の版の実体は消さないので、版を戻すときや上げ直すときは symlink を張り替えるだけで済みます。
  - symlink がすでに目標の版を指していれば何もしません。
- CNI plugins は `/opt/cni/bin` に展開し、版を `/opt/cni/bin/.porkadot-cni-plugins-version` に記録します。記録が `kubernetes.networking.cni_version` と違う（または無い）ときだけ展開し直します。
- `--force` を付けると、すべてをダウンロードし直します。

インストール後、kubelet は TLS ブートストラップを使って apiserver に接続します。
この時点では apiserver が存在しないため、kubelet は起動待ちの状態になります。

### ステップ 2a: ブートストラップノードへのインストール

`porkadot install bootstrap node` がブートストラップノードに対して以下を実行します。

1. ブートストラップノードの kubelet 設定を上書き（apiserver エンドポイント: `127.0.0.1:6443`）
2. ブートストラップ用静的 Pod マニフェストを `/etc/kubernetes/manifests/` に配置
3. `install.sh` を実行（ブートストラップ秘密情報のコピー等）
4. `https://127.0.0.1:{bind_port}/readyz` が 200 を返すまでポーリング（5 秒間隔）

kubelet が静的 Pod マニフェストを読み込み、ブートストラップ apiserver・controller-manager・scheduler・proxy が起動します。

**注意**: この時点でブートストラップノードの kubelet は `127.0.0.1:6443` を apiserver として参照しています。

### ステップ 2b: ブートストラップ Kubernetes のインストール

`porkadot install bootstrap kubernetes` がブートストラップ apiserver 経由で以下をデプロイします。

- **MetalLB**: LoadBalancer サービスを有効化し、VIP（例: `192.168.23.101`）を確立
- **CNI（Flannel または cnidaria）**: Pod ネットワークを確立
- **kube-apiserver DaemonSet**: 全コントロールプレーンノードに永続的 apiserver をデプロイ
- **kube-controller-manager DaemonSet**
- **kube-scheduler DaemonSet**
- その他有効なアドオン

MetalLB が VIP を確立すると、コントロールプレーンエンドポイント（`control_plane_endpoint`）が有効になります。

### ステップ 2c: ブートストラップクリーンアップ

`porkadot install bootstrap cleanup` が以下を実行します。

1. 全マスターノードの `/readyz` をポーリング → 全ノードの apiserver が応答するまで待機
2. ブートストラップ apiserver 経由で Service `kube-system/porkadot-kubernetes` の EndpointSlice をポーリング → 全マスターの kube-apiserver の endpoint が `ready` になるまで待機（ブートストラップ apiserver の endpoint は数えない）
3. Deployment `kube-controller-manager` と `kube-scheduler` をポーリング → それぞれ Ready のレプリカが 1 つ以上になるまで待機
4. `cleanup.sh` を実行:
   - `/etc/kubernetes/bootstrap/` を削除
   - `*.bootstrap.yaml` 静的 Pod マニフェストを削除
5. VIP の `/readyz` をポーリング → 本来のコントロールプレーンが VIP で応答することを確認

1〜3 の待ちには上限（`--timeout`、既定 600 秒）があり、超えると静的 Pod を消さずに失敗します。

2 を待つ理由: cleanup の時点では VIP の背後にブートストラップ apiserver も居るので、VIP の応答は引き継ぎの確認になりません。また、マスターの apiserver が `/readyz` に ok を返していても、kubelet がその Pod の Ready をまだ報告していなければ EndpointSlice の endpoint は `ready: false` のままです。この状態でブートストラップ apiserver を消すと、kubelet・kube-controller-manager・kube-proxy は VIP 経由でしか API に届かないのに kube-proxy が VIP を REJECT するため、Pod の Ready を報告できず、EndpointSlice も更新されないまま全ノードが NotReady になります。

ブートストラップ静的 Pod が削除されると、ブートストラップ apiserver が停止します。
この時点でブートストラップノードの kubelet は `127.0.0.1` を見ていますが、実際のコントロールプレーン（DaemonSet）は VIP 経由で動作しています。

### ステップ 3: ブートストラップノードの kubelet 設定復旧

`porkadot install bootstrap all` は `node` → `kubernetes` → `cleanup` までを実行します。ブートストラップノードの kubelet 設定を `127.0.0.1` から VIP に戻すには、完了後に `porkadot install kubelet` を再実行します。

```bash
bundle exec porkadot install kubelet --config ../porkadot.yaml
```

これでブートストラップノードの kubelet も VIP 経由で apiserver に接続するようになります。

---

## 中断・再実行時の注意事項

### bootstrap が完了する前に `install kubelet` を再実行してはいけない

`porkadot install all` は `install kubelet` → `install bootstrap` の順で動作します。

**bootstrap が完了する前に `install kubelet` を再実行すると**、ブートストラップノードの kubelet 設定が `127.0.0.1` から VIP に戻ってしまい、ブートストラップ apiserver（静的 Pod）が起動できなくなります。この状態は bootstrap が永久に完了しないデッドロック状態です。

bootstrap フェーズのみを再実行する場合:

```bash
# ブートストラップノードへの静的 Pod インストールのみ再実行
bundle exec porkadot install bootstrap node --config ../porkadot.yaml

# ブートストラップ apiserver 経由でアドオン・コントロールプレーン DaemonSet をデプロイ
bundle exec porkadot install bootstrap kubernetes --config ../porkadot.yaml

# VIP 確立後にブートストラップ静的 Pod を削除
bundle exec porkadot install bootstrap cleanup --config ../porkadot.yaml

# ブートストラップノードの kubelet 設定を VIP に戻す（必須）
bundle exec porkadot install kubelet --config ../porkadot.yaml
```

---

## クラスタ再起動後のリカバリ

### 症状

クラスタを完全停止後に再起動すると、一部のノードが `NotReady` のままで VIP が有効化されない場合があります。

### 原因

self-hosted クラスタではコントロールプレーンも DaemonSet として動作するため、クラスタ再起動直後は apiserver が存在しません。MetalLB controller がブートストラップノード以外にスケジュールされていると、そのノードは VIP なしでは Ready になれず、MetalLB も起動できないデッドロックが発生します。

### 解決手順

1. `porkadot install bootstrap node` を再実行してブートストラップ apiserver（静的 Pod）を起動します。

   ```bash
   bundle exec porkadot install bootstrap node --config ../porkadot.yaml
   ```

2. ブートストラップノードに SSH して、ブートストラップ kubeconfig を使って MetalLB controller Pod を削除します。

   ```bash
   ssh ubuntu@192.168.22.121 \
     "kubectl --kubeconfig /etc/kubernetes/bootstrap/kubeconfig-bootstrap.yaml \
      -n metallb-system delete pod -l component=controller"
   ```

   ブートストラップ kubeconfig は `127.0.0.1:6443` を向いており、ブートストラップノード上でのみ使用できます。

3. MetalLB controller がブートストラップノードに再スケジュールされ、VIP が有効化されます。

4. 他のノードが順次 Ready になったら、ブートストラップをクリーンアップします。`install bootstrap cleanup` は、`porkadot-kubernetes` の EndpointSlice に全マスターの apiserver が `ready` で入るまで待ってから静的 Pod を消します（ステップ 2c）。上限を超えて止まった場合は、表示された項目を直してから再実行します。

   ```bash
   bundle exec porkadot install bootstrap cleanup --config ../porkadot.yaml
   bundle exec porkadot install kubelet --config ../porkadot.yaml
   ```
