# porkadot 操作リファレンス

## コマンド体系

```
porkadot <subcommand> [options] --config <config.yaml>
```

> **重要**: `--config` は Thor の制約によりサブコマンドの **後**に置く必要がある。
> `porkadot --config ./porkadot.yaml install kubelet` は動作しない。

主なサブコマンド:
- `render <group>` — アセット（証明書・マニフェスト等）を生成
- `render certs [all|kubernetes|etcd] [--no-ca]` — 証明書のみ再生成（秘密鍵は保持）
- `setup-node` — ノードの初期設定
- `setup-containerd` — containerd の設定
- `install <target>` — クラスター構成要素のインストール
- `install kubernetes [all|apiserver|controller-manager|scheduler|proxy]` — kubernetes マニフェストの再適用
- `rotate-certs [all|etcd|kubernetes|kubelet-ca]` — レンダリング済み証明書を安全順に反映
- `set-config` — kubeconfig のエンドポイントを VIP に切り替え
- `migrate-secrets` — 旧レイアウト（`assets/secrets/`）の secret を `assets/<group>/` へ移動（sops 有効時は暗号化）

オプション:
- `--config <path>` — 設定ファイルのパス（デフォルト: ./porkadot.yaml）
- `--node <ip>` — 対象ノードを絞り込む

---

## 初期セットアップ（新規クラスター）

### Step 1: render

```bash
porkadot render kubelet --config ./porkadot.yaml
porkadot render etcd --config ./porkadot.yaml
porkadot render bootstrap --config ./porkadot.yaml
porkadot render kubernetes --config ./porkadot.yaml
```

足りない証明書・鍵は render の中で作られる（既にあるものは作り直さない）ので、先に `render certs` を実行する必要はない。
`render bootstrap` も単独で、bootstrap の secrets に必要な証明書・鍵をすべて揃える。

### Step 2: setup-node（全ノード）

```bash
porkadot setup-node --config ./porkadot.yaml
```

### Step 3: setup-containerd（全ノード）

```bash
porkadot setup-containerd --config ./porkadot.yaml
```

containerd 1.x（config version 2）と 2.x（config version 3、2.3 以降は version 4）のどちらにも対応する。

- `/etc/containerd/config.toml` が無いときだけ `containerd config default` で作る。既存の config は作り直さない（NVIDIA Container Toolkit などが足した設定を残すため）。
- 既存の config に `version` 行が無い場合（Docker の `containerd.io` パッケージが同梱する、`disabled_plugins = ["cri"]` だけの config など）は、元のファイルを `/etc/containerd/config.toml.porkadot-bak.<日時>` に退避してから `containerd config default` で作り直す。作り直したときはその旨をログに出す。
- config の version に合った runc options セクションに `SystemdCgroup = true` を設定する。
  - version 2: `plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options`
  - version 3 / 4: `plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options`
- runc options セクションが無い config では、セクションを作らずにエラーで止まる（containerd は再起動しない）。runc の options を inline table（`options = { ... }`）で書いた config も同じく止まる。直し方は troubleshooting「setup-containerd が runc options セクションが無いと言って止まる」を参照。
- containerd 1.x のノードに version 3 / 4 の config がある場合、containerd 2.0〜2.2 のノードに version 4 の config がある場合、config の version が 2 / 3 / 4 以外（5 など）の場合、containerd の major version が 1 / 2 以外の場合は失敗する。
- 既存の config は作り直さないので、containerd を上げても `sandbox_image`（pause image）などは古い既定値のまま残る。新しい既定値を取り込みたいときは、`/etc/containerd/config.toml` を退避・削除してから `setup-containerd` を再実行する。
- assets に `containerd/config.toml` を置いた場合（`kubelet-default/` または `kubelet/<node>/` の下）は、それをそのままコピーし、`SystemdCgroup` は書き換えない。

### Step 4: install

```bash
# 全ノードに kubelet をインストール（apiserver = VIP に設定）
porkadot install kubelet --config ./porkadot.yaml

# bootstrap フェーズ
porkadot install bootstrap node --config ./porkadot.yaml
porkadot install bootstrap kubernetes --config ./porkadot.yaml
porkadot install bootstrap cleanup --config ./porkadot.yaml

# bootstrap ノードの kubelet を VIP に戻す
porkadot install kubelet --config ./porkadot.yaml --node <bootstrap-node-ip>
```

### Step 5: set-config

```bash
porkadot set-config --config ./porkadot.yaml
```

---

## bootstrap フェーズの詳細

### install bootstrap node

- bootstrap ノードの kubelet 設定を上書き（apiserver を `127.0.0.1:6443` に変更）
- bootstrap 用の static pod マニフェストを配置し install.sh を実行
- `https://127.0.0.1:6443/readyz` が返るまでポーリング

### install bootstrap kubernetes

bootstrap API 経由で以下をデプロイ:
- MetalLB（VIP を有効化）
- CNI（Flannel、または `addons.enabled` で選んだ cnidaria）
- Kubernetes コントロールプレーン（kube-apiserver, controller-manager, scheduler）

### install bootstrap cleanup

- 全マスターノードの `/healthz` をポーリング
- VIP（`192.168.23.101:6443`）の `/healthz` をポーリング
- VIP が応答したら bootstrap 用 static pod を削除

### bootstrap ノードの kubelet 復旧

cleanup 後は bootstrap ノードの kubelet が `127.0.0.1` を向いたままになる。
`--node` で bootstrap ノードのみ指定して kubelet 設定を VIP に戻す:

```bash
porkadot install kubelet --config ./porkadot.yaml --node <bootstrap-node-ip>
```

---

## bootstrap 部分再実行（中断・失敗時）

`install all` を最初からやり直すと bootstrap 前に `install kubelet` が走り、
bootstrap ノードの apiserver が VIP を向いてしまう。
bootstrap のみ再実行する場合は以下の順で個別実行する:

```bash
porkadot install bootstrap node --config ./porkadot.yaml
porkadot install bootstrap kubernetes --config ./porkadot.yaml
porkadot install bootstrap cleanup --config ./porkadot.yaml
porkadot install kubelet --config ./porkadot.yaml --node <bootstrap-node-ip>
```

---

## 証明書更新（cert renewal）

### 証明書の有効期限

- CA 証明書: 2年
- サーバー・クライアント証明書: 1年

### render certs の挙動

- リーフ証明書は常に再生成される（`refresh=true`）
- **秘密鍵は既存ファイルを再利用**（ローテーションなし）
- デフォルトでは CA 証明書も再生成される
- `--no-ca` 指定時は CA 証明書を変更せず、既存CAでリーフ証明書だけ再発行する
- CA 秘密鍵変更は対象外。将来の CA ローテーションとして扱う

稼働中のクラスターで `render all` や `render certs` を実行すると証明書が再生成される（`--no-ca` を付けなければ CA も作り直す）。
証明書を更新するとき以外は使わず、`render kubelet` / `etcd` / `bootstrap` / `kubernetes` を個別に実行すること。これらは既存の証明書・鍵を作り直さない。

### 証明書更新手順

**Step 1**: 証明書を再生成する

```bash
# 推奨: CA は維持し、リーフ証明書だけ更新
porkadot render certs --no-ca --config ./porkadot.yaml

# または個別に
porkadot render certs kubernetes --no-ca --config ./porkadot.yaml
porkadot render certs etcd --no-ca --config ./porkadot.yaml
```

**Step 2**: 依存するマニフェストを再生成する

```bash
porkadot render kubelet --config ./porkadot.yaml
porkadot render etcd --config ./porkadot.yaml
porkadot render bootstrap --config ./porkadot.yaml
porkadot render kubernetes --config ./porkadot.yaml
```

**Step 3**: レンダリング済み証明書をクラスターへ反映する

`etcd` → `kubernetes` → `kubelet-ca` の順に実行する。
`rotate-certs kubernetes` は `--node` でコントロールプレーンノードを指定する必要がある。
(`install kubernetes` と同様に、node 未指定時は bootstrap ノードで kubectl を実行するため、
bootstrap ノードがワーカーの場合は 127.0.0.1:6443 に kube-apiserver がおらず失敗する)

```bash
porkadot rotate-certs etcd --config ./porkadot.yaml
porkadot rotate-certs kubernetes --config ./porkadot.yaml --node <control-plane-node>
porkadot rotate-certs kubelet-ca --config ./porkadot.yaml
```

CA 証明書を更新した場合も、CA を維持した場合も、反映手順は同じ。
この操作は etcd と control-plane Pod を再起動するため、実行前に必ず確認を取る。

**Step 4**: admin kubeconfig を更新する場合のみ実行する

```bash
porkadot set-config --config ./porkadot.yaml
```

`rotate-certs all` は `set-config` を自動実行しない。

> **注意**: API サーバーの TLS 証明書自体が期限切れで `install kubernetes` が失敗する場合は、
> bootstrap 経由での復旧が必要。`references/troubleshooting.md` の
> 「API サーバー証明書が期限切れでクラスターに接続できない」を参照。
> bootstrap 経由で復旧した後、admin kubeconfig も更新する場合は
> `porkadot set-config --config ./porkadot.yaml` を実行すること。

---

## バージョンアップ（k8s バージョン更新）

前提: render 済み（assets/ に新バージョンのマニフェストが生成されている）

マイナー版は 1 つずつ上げる（1.29 → 1.30 → 1.31 …）。

**コントロールプレーンを先に、kubelet を後に上げる。** Kubernetes の version skew policy では kubelet が kube-apiserver より新しくてはいけない。
`install kubelet` を先に流すと、新しい kubelet が古い kube-apiserver につながる状態になる。
kube-proxy は kubelet と 3 マイナー版まで前後してよいので、`install kubernetes` で先に上がってよい。

`install kubelet` は kubelet の設定とバイナリだけでなく、コントロールプレーンのノードでは **etcd の static Pod のマニフェストも置く**。
etcd の版が変わる場合は、`install kubelet` を流したノードで etcd が新しいイメージで再起動する。
コントロールプレーンのノードは 1 台ずつ流し、etcd が全メンバー healthy に戻ってから次へ進む。

**Step 1**: etcd のバックアップを取る

```bash
porkadot etcd backup --config ./porkadot.yaml
```

**Step 2**: コントロールプレーン（kube-apiserver・kube-controller-manager・kube-scheduler・kube-proxy・アドオン）を更新

```bash
porkadot install kubernetes --config ./porkadot.yaml --node <control-plane-ip>
# 例: porkadot install kubernetes --config ./porkadot.yaml --node 192.168.1.111
```

**Step 3**: rollout 完了確認

```bash
kubectl rollout status daemonset/kube-apiserver -n kube-system
kubectl rollout status deployment/kube-controller-manager -n kube-system
kubectl rollout status deployment/kube-scheduler -n kube-system
kubectl rollout status daemonset/kube-proxy -n kube-system
kubectl version
```

**Step 4**: コントロールプレーンのノードの kubelet（と etcd）を 1 台ずつ更新

```bash
porkadot install kubelet --config ./porkadot.yaml --node <control-plane-ip>
```

1 台ごとに、Node が Ready で新しい版になったことと、etcd が全メンバー healthy であることを確かめてから次のノードに進む。
etcd はコントロールプレーンのノード上で確かめる（`/etc/etcd/etcd.env` に接続情報がある）。

```bash
kubectl get nodes -o wide
ssh <user>@<control-plane-ip> 'sudo bash -c ". /etc/etcd/etcd.env && /opt/bin/etcdctl endpoint health --cluster"'
ssh <user>@<control-plane-ip> 'sudo bash -c ". /etc/etcd/etcd.env && /opt/bin/etcdctl endpoint status --cluster -w table"'
```

**Step 5**: ワーカーノードの kubelet を 1 台ずつ更新

```bash
porkadot install kubelet --config ./porkadot.yaml --node <worker>
kubectl get nodes -o wide
```

Step 4・5 の `install kubelet` は、kubectl・kubelet・etcdctl・crictl の `/opt/bin/<名前>` を設定の版に張り替える。
ノードに残っている版はダウンロードせずに使うので、版を戻すときも上げ直すときも `--force` は要らない。
K8s の版を変えずに etcd・crictl・CNI plugins の版だけを変えた場合も追従する。
`--force` はすべてをダウンロードし直したいとき（バイナリが壊れている疑いがあるときなど）に使う。

**Step 6**: 削除されたワーカーノードがある場合（porkadot.yaml から削除済み）

```bash
kubectl get nodes
kubectl delete node <node-name>
```

---

## `install kubernetes` の注意点

`install kubernetes` はデフォルトで **bootstrap ノード**上で kubectl を実行する。
kubeconfig の server は `https://127.0.0.1:6443` を使用するため、
bootstrap ノードにローカルの kube-apiserver が動いている必要がある。

| bootstrap ノードの種別 | 動作 |
|---|---|
| コントロールプレーンノード | そのまま動作（localhost に apiserver が動いている） |
| ワーカーノード（pablo 等） | **`--node <control-plane-ip>` が必須** |

```bash
# bootstrap ノードがワーカーの場合は --node でコントロールプレーンを指定
porkadot install kubernetes --config ./porkadot.yaml --node 192.168.1.111
```

### prune と Namespace

`install kubernetes` は `kubectl apply --prune -l kubernetes.unstable.cloud/installed-by=porkadot` で適用するので、
`addons.enabled` から外したアドオンのリソースは削除される。ただし **Namespace は prune しない**
（中身ごと消える危険な操作で、`kube-system` のように共有される Namespace もあるため）。
アドオンを無効にしても、そのアドオンの Namespace（例: `metallb-system`、`kubelet-serving-cert-approver`）は残る。
不要なら中身が空であることを確かめてから手で消す。

```bash
kubectl get all,configmap,secret,serviceaccount -n metallb-system
kubectl delete namespace metallb-system
```

storage-version-migrator を入れていたクラスタでは `kube-system` に porkadot ラベルが付いている。
以前は prune が `kube-system` を消そうとして `install kubernetes` が失敗したが、
現在は Namespace を prune しないので手作業は要らない。

---

## secret の扱いと sops による暗号化

証明書・秘密鍵・kubeconfig・secret マニフェスト・`install.secrets.sh` は、通常の asset と同じ `assets/<group>/` に出力される（モード 0600）。

- `porkadot.yaml` に `local.sops.enabled: true` を設定すると、これらは sops の binary 形式で暗号化される。ファイル名は変わらず、中身が `data` と `sops` を持つ JSON になる。
- 鍵は `porkadot.yaml` と同じディレクトリ（または `local.sops.config`）の `.sops.yaml` の `creation_rules` で決まる。`path_regex` は `assets/.*` のように `.sops.yaml` からの相対パスで書く。
- render・install・rotate-certs・set-config を実行する環境では、sops が復号できるよう鍵（age なら `SOPS_AGE_KEY_FILE` など）を用意する。
- install 時はメモリ上で復号して upload するので、ノードには平文が届く。ローカルに平文は書かれない。
- 再 render で内容が変わらない secret は書き換えられない（暗号文の無意味な差分が出ない）。

### secret を手で復号・編集するとき

secret は拡張子に関係なく binary 形式で暗号化されているので、sops に形式を明示する。

```bash
# 復号（標準出力に元のバイト列がそのまま出る）
sops decrypt --input-type json --output-type binary assets/kubernetes/kubeconfig.yaml

# 編集（binary 形式のまま暗号化し直される）
sops edit --input-type binary --output-type binary assets/kubernetes/kubeconfig.yaml
```

拡張子が `.yaml` のファイル（`kubeconfig.yaml`、`*.secrets.yaml`）は、sops が拡張子から YAML 形式とみなす。

- `sops -d <file>` だけでは、中身全体が 1 つの文字列として `data: |+` で包まれた YAML が出力される。そのまま kubectl などに渡せない。
- `sops edit <file>` だけでは、エディタに `data: |+` で包まれた文字列が開き、保存すると YAML 形式で暗号化し直される。中身も JSON ではなくなる。
  porkadot はこの形式も復号できるが、`data:` で包まれた YAML が平文として扱われ、ノードに届く内容が壊れる。

`.crt` / `.key` / `.sh` などは sops が binary 形式とみなすので、オプションなしでも正しく復号・編集できる。

### 旧レイアウト（`assets/secrets/`）からの移行

`assets/secrets/` が残っていると、render / install / rotate-certs / set-config / setup-node / setup-containerd は
`Legacy secrets layout found` で止まる。etcd サブコマンドは止まらない。

```bash
# sops を使う場合は先に local.sops.enabled と .sops.yaml を用意する
porkadot migrate-secrets --config ./porkadot.yaml

# 新しいレイアウト用のスクリプトを生成し直す（render certs は不要、CA を作り直さないこと）
porkadot render kubelet --config ./porkadot.yaml
porkadot render etcd --config ./porkadot.yaml
porkadot render bootstrap --config ./porkadot.yaml
porkadot render kubernetes --config ./porkadot.yaml
```

移動先に内容の異なるファイルがあると、何も変更せずにエラーで止まる。どちらが正しいかを確認してから片方を退避して再実行する。

---

## アセット回帰確認（render 後の差分チェック）

```bash
# 現在の assets を退避
tmp_before=$(mktemp -d /tmp/porkadot-assets-before.XXXXXX)
cp -a assets "$tmp_before/assets"

# render
porkadot render kubelet --config ./porkadot.yaml
porkadot render etcd --config ./porkadot.yaml
porkadot render bootstrap --config ./porkadot.yaml
porkadot render kubernetes --config ./porkadot.yaml

# 差分確認
diff -ru "$tmp_before/assets" assets
```

sops 有効時、暗号化された secret は `diff -ru` では暗号文の比較になる。内容が変わらない secret は書き換えられないので差分は出ない。差分が出た secret の中身は `sops decrypt --input-type json --output-type binary <file>` で確認する。
