# アドオン仕様・etcd 操作

## アドオン概要

porkadot は `addons.enabled` リストに基づいてアドオンをデプロイします。各アドオンは kustomize で管理されます。

デフォルトで有効なアドオン:
```yaml
addons:
  enabled: [flannel, coredns, metallb, kubelet-serving-cert-approver]
```

Renovate が更新するイメージのタグは、デフォルト値を書き写さず「`default.yaml` の値」とします（`lib/porkadot/default.yaml` を見てください。理由は [02-config.md](02-config.md#概要)）。

### アドオンを無効にしたとき

`addons.enabled` からアドオンを外して `render kubernetes` → `install kubernetes` を実行すると、`kubectl apply --prune` がそのアドオンのリソースを削除します（`kubernetes.unstable.cloud/installed-by=porkadot` ラベルが付いていて、prune の対象の種類に含まれるもの。[06-assets.md](06-assets.md) の `kubernetes/install.sh` を参照）。

**Namespace は prune しません。** アドオンが作った Namespace（例: metallb の `metallb-system`）はクラスタに残ります。Namespace を消すと中のリソースもすべて消えるため、不要になったことを確かめてから手で消してください。

```bash
# 中に何も残っていないことを確かめる
kubectl get all,configmap,secret,serviceaccount -n metallb-system
# 消す
kubectl delete namespace metallb-system
```

---

## アドオン一覧

### CNI plugins の持ち主

標準の CNI plugins（[containernetworking/plugins](https://github.com/containernetworking/plugins) の `bridge`・`host-local`・`portmap`・`loopback` など）は、CNI のアドオンではなく `porkadot install kubelet` がノードの `/opt/cni/bin` に置きます。版は `kubernetes.networking.cni_version` で決まり、どの CNI を有効にしても同じものが入ります（[04-deploy-flow.md](04-deploy-flow.md)）。containerd は Pod ごとに `loopback` を呼ぶので、CNI が何であってもこれが要ります。

CNI のアドオンの DaemonSet は、自分のバイナリだけを `/opt/cni/bin` に置きます。

| CNI | DaemonSet が `/opt/cni/bin` に置くもの | 使う標準の plugins |
|-----|-----------------------------|------------------|
| flannel | `flannel`（init container `install-cni-plugin`） | `bridge`・`host-local`（flannel が委ねる）、`portmap` |
| cnidaria | なし | `bridge`・`host-local`・`portmap` |

CNI の DaemonSet と `install kubelet` の両方が同じファイルを置くと、版が違うときにどちらが最後に流れたかでノードの版が変わるため、標準の plugins は `install kubelet` だけが置きます。

### flannel（CNI ネットワーク）

Pod 間のネットワーキングを提供します。

| 設定キー | デフォルト | 説明 |
|---------|-----------|------|
| `backend` | `vxlan` | ネットワークバックエンド（`vxlan` / `host-gw`） |
| `plugin_image_repository` | `flannel/flannel-cni-plugin` | CNI プラグインイメージ |
| `plugin_image_tag` | `default.yaml` の値 | CNI プラグインイメージタグ |
| `daemon_image_repository` | `flannel/flannel` | Flannel デーモンイメージ |
| `daemon_image_tag` | `default.yaml` の値 | Flannel デーモンイメージタグ |
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

### cnidaria（CNI ネットワーク・NetworkPolicy）

[cnidaria-cni](https://github.com/yuanying/cnidaria-cni) は flannel の `host-gw` 相当のデータプレーン（ノードごとに 1 本の bridge、ノード間はホストの経路表）に加え、NetworkPolicy とノード向けポリシー（`NodeNetworkPolicy` CRD）を nftables で enforce する CNI です。

既定では無効です（opt-in）。有効にするには `addons.enabled` の `flannel` を `cnidaria` に置き換えます。**flannel と cnidaria を同時に有効にした設定は検証エラーになります。** cnidaria を有効にすると flannel のマニフェストは出力されません。

```yaml
addons:
  enabled: [cnidaria, coredns, metallb, kubelet-serving-cert-approver]
```

| 設定キー | デフォルト | 説明 |
|------|-----------|------|
| `image_repository` | `ghcr.io/yuanying/cnidaria-cni` | cnidaria イメージ |
| `image_tag` | `default.yaml` の値 | cnidaria イメージタグ |
| `network_name` | `cnidaria` | conflist のネットワーク名（`--network-name`）。host-local の IP 割り当ては `/var/lib/cni/networks/<name>` に保存される |
| `resources.requests.cpu` | `50m` | CPU リクエスト |
| `resources.requests.memory` | `64Mi` | メモリリクエスト |
| `resources.limits.memory` | `256Mi` | メモリリミット |

Pod CIDR はテンプレートに埋め込みません。cnidaria は各 Node の `spec.podCIDRs`（kube-controller-manager が `kubernetes.networking.pod_subnet` から割り当てたもの）を読みます。デュアルスタックの場合も追加設定は不要です。

コントロールプレーンの taint（`node-role.kubernetes.io/control-plane` と旧名の `node-role.kubernetes.io/master`）は DaemonSet で tolerate しています。

cnidaria は CNI のバイナリを持たず、DaemonSet は `/opt/cni/bin` に何も置きません。conflist が使う `bridge`・`host-local`・`portmap` は `install kubelet` が置いたものを使います（[CNI plugins の持ち主](#cni-plugins-の持ち主)）。

`NodeNetworkPolicy` の CRD は `assets/kubernetes/manifests/crds/cnidaria/crds.yaml` として出力され、インストール時に他のリソースより先に適用されます。

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

マニフェストは上流 [alex1989hu/kubelet-serving-cert-approver](https://github.com/alex1989hu/kubelet-serving-cert-approver) の `deploy/standalone-install.yaml`（v0.12.1）を元にしています。上流との違いは、node affinity で `node-role.kubernetes.io/master` の付いたノードも避けることと、イメージのタグを設定で固定すること（`imagePullPolicy: IfNotPresent`）です。

| キー | デフォルト | 説明 |
|------|-----------|------|
| `image_repository` | `ghcr.io/alex1989hu/kubelet-serving-cert-approver` | approver イメージ |
| `image_tag` | `default.yaml` の値 | approver イメージタグ（上流のリリースの版から先頭の `v` を除いたもの。リリース `v0.12.1` のイメージは `0.12.1`） |

`kubelet-rubber-stamp` の後継として推奨されるアドオンです。

---

### kubelet-rubber-stamp（証明書自動承認・旧）

`kubelet-serving-cert-approver` の旧バージョン相当です。新規インストールでは `kubelet-serving-cert-approver` を使用してください。

追加設定なし。デフォルトでは無効（`addons.enabled` に含まれていない）。

---

## 削除済みのアドオン

### storage-version-migrator

[kube-storage-version-migrator](https://github.com/kubernetes-sigs/kube-storage-version-migrator) v0.0.5 を外付けでデプロイするアドオンでした。Kubernetes 本体が storage version migration を機能として持つようになったため削除しました。

`addons.enabled` に残っていると、設定の検証エラー（`addons.enabled contains removed addon: storage-version-migrator ...`）になります。`addons.enabled` から外してください。

既存のクラスタでは、アドオンを外して `render kubernetes` → `install kubernetes` を実行すると、prune が次のリソースを削除します。いずれも `kubernetes.unstable.cloud/installed-by=porkadot` ラベルが付いていて prune の対象の種類なので、手で消す必要はありません。CRD が消えると、そのカスタムリソース（`StorageState`、`StorageVersionMigration`）も消えます。

| 種類 | 名前 |
|------|------|
| Deployment（kube-system） | `migrator`、`trigger` |
| ClusterRoleBinding | `storage-version-migration-crd-creator`、`storage-version-migration-initializer`、`storage-version-migration-migrator`、`storage-version-migration-trigger` |
| ClusterRole | `storage-version-migration-crd-creator`、`storage-version-migration-initializer`、`storage-version-migration-trigger` |
| CustomResourceDefinition | `storagestates.migration.k8s.io`、`storageversionmigrations.migration.k8s.io` |

古い生成マニフェストにはこれ以外に `Namespace kube-system` が含まれていたため、このアドオンを入れたクラスタでは `kube-system` にも porkadot ラベルが付いています。これは prune されずに残ります（porkadot は Namespace を prune しません。「アドオンを無効にしたとき」を参照）。

Namespace を prune の対象にしていた古い porkadot では、このアドオンを外したあとの `install kubernetes` が、上のリソースを削除したあと `kube-system` を消そうとして失敗しました（`namespaces "kube-system" is forbidden: this namespace may not be deleted`、exit 1）。現在の porkadot ではこのラベルが残っていても `install kubernetes` は失敗せず、手作業は要りません。ラベルを外したい場合は次のとおりです。

```bash
kubectl label namespace kube-system kubernetes.unstable.cloud/installed-by-
```

`install kubernetes` を使わずに手で消す場合は、上の表のリソースを名前を指定して消してください。古い生成マニフェストに `kubectl delete -f` / `kubectl delete -k` を使うと、`kube-system` ごと消えます。

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

`/etc/etcd/pki` の証明書と鍵は root だけが読めるため、etcdctl は root で実行します。
スナップショットはノードの `./kube_temp/kubelet/etcd.db` に書いたあと、接続ユーザーの持ち物・モード 0600 にしてダウンロードし、ノードからは消します。
スナップショットは Secret を含むため、手元のファイルもモード 0600 にします。

### リストア

```bash
# 最新バックアップからリストア
porkadot etcd restore

# バックアップ先を指定
porkadot etcd restore --path /mnt/backup

# etcd が動いておらず今の revision を読めないとき、進める幅を渡す
porkadot etcd restore --bump-revision 3000000000
```

リストア手順（内部処理）:
1. 指定ディレクトリ内の最新バックアップファイルを選択
2. 今の revision を読む（`etcd.image_tag` が 3.5.10 以上で、`--bump-revision` が無いとき）。各メンバーで
   `etcdctl endpoint status -w json` を流し、答えたメンバーの revision の最大を取る。読んだ値はメンバーごとにログに出す。
   どのメンバーも答えないときは、etcd を止めずにエラーで終了する（`--bump-revision` で幅を渡せば先へ進める）
3. etcd を停止（全メンバーノード）
4. etcd データをリストア（全メンバーノード）。バックアップを各メンバーに置き、既存の `/var/lib/etcd` は `/opt/porkadot/data-<日時>` に退避し、
   そのノードのメンバー名・peer URL と全メンバーの initial-cluster（`etcd-server.yaml` と同じ値）で `/var/lib/etcd` に復元する。
   復元は `/opt/bin/etcdutl snapshot restore` で行う（etcdctl の `snapshot restore` は 3.6 で消えた。etcdutl は 3.5 にもある）
   - `--bump-revision <幅> --mark-compacted` を付ける（etcd の disaster recovery の文書の推奨。`etcd.image_tag` が 3.5.10 未満なら付けない。etcdutl にこのフラグが無いため）。
     そのまま戻すと revision が backup の時点に戻り、動き続けている kube-apiserver の watch cache や各コンポーネントの informer は、戻した後の変化（消えたはずのオブジェクトの削除など）を受け取れない。
     revision を十分に進めて compacted にすると、watch しているクライアントには compacted が返り、list し直す
   - 幅は「1000000000」と「今の revision − snapshot の revision + 1000000000」の大きい方。snapshot の revision は最初のメンバーで
     `etcdutl snapshot status -w json` で読む（`/var/lib/etcd` を退避する前。読めなければ etcd を止めたままエラーで終了し、`porkadot etcd start` で戻せる）。
     決めた幅・今の revision・snapshot の revision・戻した後の revision をログに出す
   - etcd の文書の考え方は「snapshot の後に書かれた revision の数より大きく進める」。1000000000 は毎秒 1500 書き込み未満なら 1 週間分にあたる。
     ただし 1 回 restore した後は revision がすでに 10 億を超えているので、それより古い snapshot へもう一度 restore すると、10 億を足しても
     前にクライアントが見た revision を下回ることがある。見た revision より先から watch したクライアントには、etcd はエラーもイベントも返さず待ち続け、
     kubelet などの informer が止まる。そこで snapshot の後に書かれた数を今の revision から測り、その上に 1000000000 の余裕を足す。
     戻した後の revision は今の revision + 1000000000 以上になる。遅れているメンバーとの差や、読んでから止めるまでの書き込みはこの余裕に収まる
   - `--bump-revision` を渡したときは、今の revision も snapshot の revision も読まずにその値を使う。クライアントが見た最大の revision − snapshot の revision より大きい値を渡す
5. etcd を起動（全メンバーノード）
6. 全メンバーで `etcdctl endpoint health` が通るまで待つ（`--timeout` 秒）
7. 全 master で kube-apiserver のコンテナを crictl で止め、kubelet が起動し直して `https://127.0.0.1:<bind_port>/readyz` が返るのを待つ。1 台ずつ流すので、API が全部止まることはない
8. 続けて kube-controller-manager と kube-scheduler のコンテナを、動いている master で同じように止め、起動し直すのを待つ（Kubernetes の文書「Restoring an etcd cluster」は、古いデータに頼らないようこれらと kubelet の再起動を勧めている）
   - kubelet は再起動しない。kubelet・kube-proxy・アドオンの informer は 4 の compacted で list し直す。気になるときは各ノードで `sudo systemctl restart kubelet` を流す（コンテナは止まらない）
   - 待ちが `--timeout` を過ぎると、何を待っていたかと確かめるコマンドを出してエラーで止まる

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

etcd の停止/起動は `etcd-server.yaml` を `/etc/kubernetes/manifests/` と `/opt/porkadot/` の間で移動することで行われます（kubelet が静的 Pod として管理するため）。

`--node` には `porkadot.yaml` の `nodes` のキーを指定します。そのノードの接続設定（`connection`）で接続し、定義にないノードや etcd メンバーでないノードを指定すると、何もせずにエラーになります（[03-cli.md](03-cli.md#--node-オプション)）。

### etcd 接続設定

etcdctl コマンドは以下の証明書ファイルを使用します:

| オプション | ファイル |
|-----------|---------|
| `--cacert` | `/etc/etcd/pki/ca.crt` |
| `--cert` | `/etc/etcd/pki/etcd.crt` |
| `--key` | `/etc/etcd/pki/etcd.key` |
| `--endpoints` | `https://127.0.0.1:2379` |

`/etc/etcd/pki` の `ca.crt`・`etcd.crt`・`etcd.key` は `install.sh` が root:root 0600 で置きます（既にあるファイルも 0600 にそろえ直します）。
etcd の静的 Pod は root で動くので読めます。etcdctl を使う porkadot のコマンド（`etcd backup`、`rotate-certs etcd` のヘルスチェック）は root で実行します。

`/etc/etcd/etcd.env` は同じ値を `ETCDCTL_CACERT` / `ETCDCTL_CERT` / `ETCDCTL_KEY` / `ETCDCTL_ENDPOINTS` として export します（秘密は含まないのでモードはそのまま）。
porkadot のコマンドはこのファイルを読み込みません。手で読み込んだシェルで同じ値をフラグでも渡すと、etcdctl（3.5 以降）は
`conflicting environment variable "ETCDCTL_ENDPOINTS" is shadowed by corresponding command-line flag` で止まります。
読み込んだときはフラグを付けず、別のエンドポイントを使うときは環境変数を unset してからフラグで渡します。

### etcd メンバーの URL 構成

各 etcd メンバーは以下のポートで通信します。

| ポート | 用途 |
|--------|------|
| `2379` | クライアント通信（kube-apiserver との通信） |
| `2380` | Peer 間通信（etcd メンバー間の同期） |
| `2381` | メトリクス（HTTP、TLS なし） |

メンバーのアドレスは `etcd.unstable.cloud/member` ラベルの値（メンバー名）から決定されます。`etcd.unstable.cloud/address` ラベルで advertise アドレスを明示的に上書きできます。
