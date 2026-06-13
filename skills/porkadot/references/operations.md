# porkadot 操作リファレンス

## コマンド体系

```
porkadot --config <config.yaml> <subcommand> [options]
```

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
porkadot --config ./porkadot.yaml render kubelet
porkadot --config ./porkadot.yaml render etcd
porkadot --config ./porkadot.yaml render bootstrap
porkadot --config ./porkadot.yaml render kubernetes
```

`render all` や `render certs` は証明書が毎回再生成されるため使わないこと。

### Step 2: setup-node（全ノード）

```bash
porkadot --config ./porkadot.yaml setup-node
```

### Step 3: setup-containerd（全ノード）

```bash
porkadot --config ./porkadot.yaml setup-containerd
```

### Step 4: install

```bash
# 全ノードに kubelet をインストール（apiserver = VIP に設定）
porkadot --config ./porkadot.yaml install kubelet

# bootstrap フェーズ
porkadot --config ./porkadot.yaml install bootstrap node
porkadot --config ./porkadot.yaml install bootstrap kubernetes
porkadot --config ./porkadot.yaml install bootstrap cleanup

# bootstrap ノードの kubelet を VIP に戻す
porkadot --config ./porkadot.yaml install kubelet --node <bootstrap-node-ip>
```

### Step 5: set-config

```bash
porkadot --config ./porkadot.yaml set-config
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
porkadot --config ./porkadot.yaml install kubelet --node <bootstrap-node-ip>
```

---

## bootstrap 部分再実行（中断・失敗時）

`install all` を最初からやり直すと bootstrap 前に `install kubelet` が走り、
bootstrap ノードの apiserver が VIP を向いてしまう。
bootstrap のみ再実行する場合は以下の順で個別実行する:

```bash
porkadot --config ./porkadot.yaml install bootstrap node
porkadot --config ./porkadot.yaml install bootstrap kubernetes
porkadot --config ./porkadot.yaml install bootstrap cleanup
porkadot --config ./porkadot.yaml install kubelet --node <bootstrap-node-ip>
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
porkadot --config ./porkadot.yaml render certs all

# または個別に
porkadot --config ./porkadot.yaml render certs kubernetes
porkadot --config ./porkadot.yaml render certs etcd
```

**Step 2**: 依存するマニフェストを再生成する

```bash
porkadot --config ./porkadot.yaml render kubelet
porkadot --config ./porkadot.yaml render etcd
porkadot --config ./porkadot.yaml render bootstrap
porkadot --config ./porkadot.yaml render kubernetes
```

**Step 3**: 新しい証明書・bootstrap certs を全ノードに配布する

```bash
porkadot --config ./porkadot.yaml install kubelet
```

**Step 4**: Kubernetes マニフェストを再適用する（コントロールプレーンに新しい証明書を読み込ませる）

```bash
porkadot --config ./porkadot.yaml install kubernetes
# または個別コンポーネント
porkadot --config ./porkadot.yaml install kubernetes apiserver
porkadot --config ./porkadot.yaml install kubernetes controller-manager
porkadot --config ./porkadot.yaml install kubernetes scheduler
```

---

## アセット回帰確認（render 後の差分チェック）

```bash
# 現在の assets を退避
tmp_before=$(mktemp -d /tmp/porkadot-assets-before.XXXXXX)
cp -a assets "$tmp_before/assets"

# render
porkadot --config ./porkadot.yaml render kubelet
porkadot --config ./porkadot.yaml render etcd
porkadot --config ./porkadot.yaml render bootstrap
porkadot --config ./porkadot.yaml render kubernetes

# 差分確認
diff -ru "$tmp_before/assets" assets
```
