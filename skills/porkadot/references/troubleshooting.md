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

## API サーバー証明書が期限切れでクラスターに接続できない

### 症状

- `kubectl get nodes` が `x509: certificate has expired or not yet valid` で失敗する
- VIP には接続できるが API 呼び出しが全て TLS エラーになる

### 原因

kube-apiserver の TLS サーバー証明書自体が期限切れになっている。
通常の API がまだ使える場合は `rotate-certs kubernetes` で更新できる。
API が TLS エラーで使えない場合は、bootstrap 経由で復旧する必要がある。

### 復旧手順

**Step 1**: 証明書と依存マニフェストを再生成する

```bash
porkadot render certs kubernetes --no-ca --config ./porkadot.yaml
porkadot render kubelet --config ./porkadot.yaml
porkadot render bootstrap --config ./porkadot.yaml
porkadot render kubernetes --config ./porkadot.yaml
```

**Step 2**: API が使える場合は通常のローテーションを実行する

```bash
porkadot rotate-certs kubernetes --config ./porkadot.yaml --node <control-plane-node>
```

**Step 3**: 通常APIが使えない場合は bootstrap 経由で DaemonSet を更新する

```bash
porkadot install bootstrap node --config ./porkadot.yaml
porkadot install bootstrap kubernetes --config ./porkadot.yaml
```

**Step 4**: 古い kube-apiserver Pod を bootstrap kubeconfig を使って手動削除する

```bash
# bootstrap ノード上で実行
ssh <user>@<bootstrap-node-ip> \
  "/opt/bin/kubectl --kubeconfig /etc/kubernetes/bootstrap/kubeconfig-bootstrap.yaml \
   -n kube-system get pod | grep kube-apiserver"

ssh <user>@<bootstrap-node-ip> \
  "/opt/bin/kubectl --kubeconfig /etc/kubernetes/bootstrap/kubeconfig-bootstrap.yaml \
   -n kube-system delete pod <old-kube-apiserver-pod-name>"
```

Pod を削除すると kubelet が新しい DaemonSet spec から Pod を再生成し、新しい証明書が読み込まれる。

**Step 5**: cleanup と必要な kubeconfig 更新を実行する

```bash
porkadot install bootstrap cleanup --config ./porkadot.yaml
porkadot install kubelet --config ./porkadot.yaml --node <bootstrap-node-ip>
porkadot set-config --config ./porkadot.yaml
```

admin kubeconfig を更新した場合、または bootstrap 経由の復旧後に kubeconfig が
`127.0.0.1:6443` を向いたままの場合は、`set-config` で VIP に切り替える。

---

## kube-proxy が "too many open files" で CrashLoopBackOff

### 症状

- kube-proxy が CrashLoopBackOff
- ログに `too many open files` または `failed to create inotify instance`
- kube-proxy が落ちているノードでは Service IP（ClusterIP）への通信が不通になる

### 原因

`fs.inotify.max_user_instances` が Linux デフォルト (128) のまま。
kube-proxy はサービスや Endpoints の変化を監視するために多数の inotify インスタンスを使用する。

### 対処

```bash
# 即時反映
ssh <user>@<node-ip> "sudo sysctl -w fs.inotify.max_user_instances=8192"

# 永続化
ssh <user>@<node-ip> "echo 'fs.inotify.max_user_instances = 8192' | sudo tee /etc/sysctl.d/99-inotify.conf"
```

設定後、kube-proxy Pod を削除して再起動させる。kube-proxy が回復すれば、
そのノードでの Service IP 経由通信（kube-state-metrics 等）も自動回復する。

---

## Longhorn VolumeAttachment がスタックして Pod が ContainerCreating のまま

### 症状

- Pod が ContainerCreating から進まない
- `kubectl describe pod` の Events に `FailedAttachVolume: DeadlineExceeded`
- `kubectl get volumeattachment` で `ATTACHED=false` のエントリが長時間残っている

### 原因

長時間のクラスター停止後、Longhorn が管理する VolumeAttachment が `attached=false` のまま
スタックする。Longhorn が再アタッチを試みても古い VolumeAttachment が残っているため
新しいアタッチリクエストを処理できない。

### 確認

```bash
kubectl get volumeattachment
# ATTACHED=false かつ長時間経過しているものを特定
kubectl describe volumeattachment <name>
# AttachError に DeadlineExceeded が含まれていれば該当
```

### 対処

実行前に Longhorn の manager/engine DaemonSet が全ノードで Running か確認する。

```bash
kubectl delete volumeattachment <stuck-attachment-name>
```

削除後、Kubernetes が新しい VolumeAttachment を作成し、Longhorn が再アタッチを開始する。

---

## porkadot 実行時に SSH 接続が fingerprint mismatch で失敗する

### 症状

- porkadot 実行時に特定ノードで SSH 接続が失敗する
- エラーメッセージに `fingerprint` や `known_hosts` が含まれる

### 原因

porkadot が使用する net-ssh (Ruby) は `~/.ssh/known_hosts` のエントリを直接検証する。
以下の場合に不一致が発生する:
- ノードを再インストールしてホスト鍵が変わった
- `ssh-keyscan -H`（ハッシュ形式）で登録されており net-ssh が認識できない

### 対処

```bash
# 古いエントリを削除
ssh-keygen -R <node-ip>

# 平文形式で再登録（-H フラグなし）
ssh-keyscan <node-ip> >> ~/.ssh/known_hosts
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
