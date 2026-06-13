# porkadot トラブルシューティング

## クラスター再起動後に MetalLB が起動しない

### 症状

- クラスターを完全停止後に再起動すると、一部のノードが `NotReady` のまま
- VIP（例: `192.168.23.101`）が有効化されない

### 原因

self-hosted クラスターではコントロールプレーンも Deployment として動作するため、
クラスター再起動直後は apiserver が存在しない。
MetalLB controller が bootstrap ノード以外にスケジュールされていると、
そのノードは VIP なしでは Ready になれず、MetalLB も起動できない**デッドロック**が発生する。

### 復旧手順

**Step 1**: `install bootstrap node` を再実行して bootstrap apiserver（static pod）を起動する

```bash
porkadot --config ./porkadot.yaml install bootstrap node
```

bootstrap apiserver + controller-manager + scheduler が bootstrap ノード上に static pod として起動し、
etcd の既存状態にアクセスできるようになる。

**Step 2**: bootstrap ノードに SSH し、MetalLB controller Pod を削除する

```bash
ssh ubuntu@<bootstrap-node-ip> \
  "/opt/bin/kubectl --kubeconfig /etc/kubernetes/bootstrap/kubeconfig-bootstrap.yaml \
   -n metallb-system delete pod -l component=controller"
```

bootstrap kubeconfig は `127.0.0.1:6443` を向いており、bootstrap ノード上でのみ使用できる。
`kubectl` は `/opt/bin/kubectl` にある。

**Step 3**: MetalLB controller が bootstrap ノードに再スケジュールされ、VIP が有効化される

**Step 4**: 他のノードが順次 Ready になったら cleanup と kubelet 復旧

```bash
porkadot --config ./porkadot.yaml install bootstrap cleanup
porkadot --config ./porkadot.yaml install kubelet --node <bootstrap-node-ip>
```

---

## bootstrap が完了しない

### 症状

- `install bootstrap node` は成功するが、`install bootstrap kubernetes` がタイムアウトする
- VIP がいつまでも有効にならない

### 確認ポイント

1. bootstrap ノードで static pod が起動しているか確認

```bash
ssh ubuntu@<bootstrap-node-ip> \
  "/opt/bin/kubectl --kubeconfig /etc/kubernetes/bootstrap/kubeconfig-bootstrap.yaml get pods -A"
```

2. MetalLB, Flannel が正常に動作しているか確認

3. etcd が healthy か確認

```bash
ssh ubuntu@<bootstrap-node-ip> \
  "/opt/bin/kubectl --kubeconfig /etc/kubernetes/bootstrap/kubeconfig-bootstrap.yaml \
   -n kube-system get pods -l component=etcd"
```

### 対処

bootstrap ノードの kubelet が `127.0.0.1:6443` を向いているか確認する。
`install kubelet` を全台に対して再実行していた場合は、bootstrap ノードの向き先が
VIP に戻ってしまっている可能性がある。その場合は `install bootstrap node` を再実行する。

---

## install kubelet 後に bootstrap ノードが VIP を向いてしまう

### 症状

- bootstrap フェーズ中に意図せず `install kubelet` を全台実行してしまった
- bootstrap ノードの kubelet が VIP（`192.168.23.101:6443`）を向いており、
  bootstrap apiserver（`127.0.0.1:6443`）に繋がらない

### 対処

`install bootstrap node` を再実行すると、bootstrap ノードの kubelet 設定が
`127.0.0.1:6443` に上書きされ、bootstrap apiserver が起動する。

```bash
porkadot --config ./porkadot.yaml install bootstrap node
```

---

## ノードが NotReady のまま

### 確認コマンド

```bash
# ノードの kubelet 状態確認
ssh <user>@<node-ip> "systemctl status kubelet"
ssh <user>@<node-ip> "journalctl -u kubelet --since '5 minutes ago'"

# bootstrap ノードから全ノード確認
ssh ubuntu@<bootstrap-node-ip> \
  "/opt/bin/kubectl --kubeconfig /etc/kubernetes/bootstrap/kubeconfig-bootstrap.yaml get nodes"
```

### よくある原因

- containerd が起動していない → `systemctl status containerd` で確認
- kubelet の設定に誤りがある（apiserver 向き先）
- CNI（Flannel）が起動していない
