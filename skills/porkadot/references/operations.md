# porkadot 操作リファレンス

## コマンド体系

```
porkadot <subcommand> [options] --config <config.yaml>
```

> **重要**: `--config` は Thor の制約によりサブコマンドの **後**に置く必要がある。
> `porkadot --config ./porkadot.yaml install kubelet` は動作しない。

主なサブコマンド:
- `render <group>` — アセット（証明書・マニフェスト等）を生成
- `render certs [all|kubernetes|etcd]` — 証明書のみ再生成（秘密鍵は保持）
- `setup-node` — ノードの初期設定
- `setup-containerd` — containerd の設定
- `install <target>` — クラスター構成要素のインストール
- `install kubernetes [all|apiserver|controller-manager|scheduler|proxy]` — kubernetes マニフェストの再適用
- `set-config` — kubeconfig のエンドポイントを VIP に切り替え

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

`render all` や `render certs` は証明書が毎回再生成されるため使わないこと。

### Step 2: setup-node（全ノード）

```bash
porkadot setup-node --config ./porkadot.yaml
```

### Step 3: setup-containerd（全ノード）

```bash
porkadot setup-containerd --config ./porkadot.yaml
```

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
- Flannel（CNI）
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

- 証明書は常に再生成される（`refresh=true`）
- **秘密鍵は既存ファイルを再利用**（ローテーションなし）
- CA 証明書も再生成されるが、CA 変更時は依存する全証明書の再発行が必要

### 証明書更新手順

**Step 1**: 証明書を再生成する

```bash
# 全証明書
porkadot render certs all --config ./porkadot.yaml

# または個別に
porkadot render certs kubernetes --config ./porkadot.yaml
porkadot render certs etcd --config ./porkadot.yaml
```

**Step 2**: 依存するマニフェストを再生成する

```bash
porkadot render kubelet --config ./porkadot.yaml
porkadot render etcd --config ./porkadot.yaml
porkadot render bootstrap --config ./porkadot.yaml
porkadot render kubernetes --config ./porkadot.yaml
```

**Step 3**: 新しい証明書・bootstrap certs を全ノードに配布する

```bash
porkadot install kubelet --config ./porkadot.yaml
```

**Step 4**: Kubernetes マニフェストを再適用する（コントロールプレーンに新しい証明書を読み込ませる）

```bash
porkadot install kubernetes --config ./porkadot.yaml --node <control-plane-ip>
# または個別コンポーネント
porkadot install kubernetes apiserver --config ./porkadot.yaml --node <control-plane-ip>
porkadot install kubernetes controller-manager --config ./porkadot.yaml --node <control-plane-ip>
porkadot install kubernetes scheduler --config ./porkadot.yaml --node <control-plane-ip>
```

> **注意**: API サーバーの TLS 証明書自体が期限切れで `install kubernetes` が失敗する場合は、
> bootstrap 経由での復旧が必要。`references/troubleshooting.md` の
> 「API サーバー証明書が期限切れでクラスターに接続できない」を参照。
> bootstrap 経由で復旧した後は `porkadot set-config --config ./porkadot.yaml` で kubeconfig を VIP に切り替えること。

---

## バージョンアップ（k8s バージョン更新）

前提: render 済み（assets/ に新バージョンのマニフェストが生成されている）

**Step 1**: 全ノードに新しい kubelet 設定・etcd マニフェストを配布

```bash
porkadot install kubelet --config ./porkadot.yaml
```

**Step 2**: コントロールプレーンのマニフェストを更新

```bash
porkadot install kubernetes --config ./porkadot.yaml --node <control-plane-ip>
# 例: porkadot install kubernetes --config ./porkadot.yaml --node 192.168.1.111
```

**Step 3**: rollout 完了確認

```bash
kubectl rollout status daemonset/kube-apiserver -n kube-system
kubectl get nodes -o wide
kubectl version
```

**Step 4**: 削除されたワーカーノードがある場合（porkadot.yaml から削除済み）

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
