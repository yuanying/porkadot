---
name: porkadot
description: |
  porkadot CLI を使った Kubernetes クラスター管理のスキル。
  トリガー: "porkadot", "クラスター", "クラスタ", "bootstrap", "MetalLB", "ノード", "k8s", "kubernetes"
  使用場面:
    (1) クラスターの初期セットアップ・インストール
    (2) bootstrap / install / render / setup-node などの操作
    (3) クラスター再起動後の復旧（MetalLB 特死、bootstrap 復旧）
    (4) 障害調査・トラブルシューティング
    (5) porkadot に関するあらゆる操作やエラー対応
  ユーザーが「どうすれば？」「うまくいかない」「起動しない」といった問題を相談したときも積極的に使用すること。
---

# porkadot クラスター管理スキル

porkadot を使って Kubernetes クラスターをオペレーションするためのスキルです。
状況を調査し、実行プランをユーザーに提示・確認し、承認を得てから実行します。

## 基本方針

1. **まず調査する** — 操作の前に現在の状態を把握する
2. **プランを提示する** — 何をどの順で実行するかを示す
3. **確認を取る** — 破壊的操作（install, cleanup, setup 系）は必ず実行前に確認する
4. **実行・報告する** — 結果を確認しながら進め、問題があれば随時報告する

## 設定ファイル

```bash
# デフォルト: カレントディレクトリの porkadot.yaml
CONFIG="./porkadot.yaml"

# ユーザーが別のパスを指定した場合はそれを使う
CONFIG="<user-specified-path>"
```

設定ファイルが存在しない場合はエラーとし、ユーザーにパスを確認する。

## フルライフサイクル操作

詳細な操作手順は `references/operations.md` を参照。

### 初期セットアップ（新規クラスター）

```
1. render（アセット生成）
2. setup-node（全ノード）
3. setup-containerd（全ノード）
4. install all（kubelet → bootstrap → cleanup）
5. set-config（kubeconfig を VIP に切り替え）
```

**確認が必要なステップ**: setup-node, setup-containerd, install

### クラスター再起動後の復旧

クラスター完全停止後の再起動時は MetalLB 特死に注意する。
詳細は `references/troubleshooting.md` の「クラスター再起動後に MetalLB が起動しない」を参照。

### バージョンアップ（k8s バージョン更新）

```
1. render kubelet / etcd / bootstrap / kubernetes（render 済みの場合は不要）
2. install kubelet（全ノードに新しい設定・etcd マニフェストを配布）
3. install kubernetes --node <control-plane-ip>（コントロールプレーンを更新）
```

詳細は `references/operations.md` の「バージョンアップ」セクションを参照。

**確認が必要なステップ**: install kubelet, install kubernetes

### 証明書更新

```
1. render certs（all または対象の kubernetes/etcd）
2. render kubelet / etcd / bootstrap / kubernetes（依存マニフェストを再生成）
3. install kubelet（新しい証明書を全ノードに配布）
4. install kubernetes --node <control-plane-ip>（コントロールプレーンに証明書を読み込ませる）
```

詳細は `references/operations.md` の「証明書更新」セクションを参照。

**確認が必要なステップ**: install kubelet, install kubernetes

### render（アセット生成）

```bash
porkadot render <group> --config $CONFIG
# group: kubelet / etcd / bootstrap / kubernetes / all
```

deterministic なグループ（kubelet, etcd, bootstrap, kubernetes）のみ render する。
証明書差分を避けるため `render all` や `render certs` は使わない。

### install

```bash
porkadot install kubelet --config $CONFIG
porkadot install bootstrap node --config $CONFIG
porkadot install bootstrap kubernetes --config $CONFIG
porkadot install bootstrap cleanup --config $CONFIG
porkadot install kubelet --config $CONFIG --node <bootstrap-node-ip>
```

**重要**: bootstrap 完了前に `install kubelet` を全台再実行すると bootstrap ノードの
apiserver 向き先が VIP に戻り、bootstrap が永久に完了しなくなる。
bootstrap だけを再実行したい場合は各ステップを個別に実行すること。

## 調査コマンド

状況把握に使えるコマンドの例：

```bash
# ノード疎通確認
ssh <user>@<node-ip> "systemctl status kubelet"

# bootstrap ノードで bootstrap kubeconfig を使う
ssh ubuntu@<bootstrap-node-ip> \
  "/opt/bin/kubectl --kubeconfig /etc/kubernetes/bootstrap/kubeconfig-bootstrap.yaml get nodes"

# VIP 応答確認
curl -k https://192.168.23.101:6443/healthz
```

## 実行フロー

```
ユーザーの依頼
    ↓
[調査] 設定ファイル確認・ノード状態把握・障害パターン照合
    ↓
[プラン提示] 実行するコマンドをステップ形式で提示
    ↓
[確認] 「このプランで実行してよいですか？」
    ↓ Yes
[実行] ステップごとに実行し結果を報告
    ↓
[完了報告] 最終状態を確認して報告
```

破壊的操作（install, setup-node, setup-containerd, cleanup）の前には
**必ず確認を取る**こと。調査・render・状態確認は確認不要。

## 参照ファイル

- `references/operations.md` — 各操作の詳細手順とコマンド例
- `references/troubleshooting.md` — 既知の障害パターンと復旧手順
