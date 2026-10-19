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

**Step 4**: 他のノードが順次 Ready になったら、VIP の背後の EndpointSlice に全マスターの apiserver が ready で入っていることを確かめる

```bash
ssh ubuntu@<bootstrap-node-ip> \
  "/opt/bin/kubectl --kubeconfig /etc/kubernetes/bootstrap/kubeconfig-bootstrap.yaml \
   -n kube-system get endpointslices -l kubernetes.io/service-name=porkadot-kubernetes \
   -o jsonpath='{range .items[*].endpoints[*]}{.nodeName}{\"\t\"}{.targetRef.name}{\"\t\"}{.conditions.ready}{\"\n\"}{end}'"
```

`bootstrap-kube-apiserver-*` 以外の行（各マスターの `kube-apiserver-*`）が全部 `true` になるまで待つ。
`false` のまま bootstrap を消すと、kube-proxy が VIP を REJECT して全ノードが NotReady に戻る。
`install bootstrap cleanup` も同じ条件（と kube-controller-manager / kube-scheduler に Ready のレプリカがあること）を
待ち、上限（既定 600 秒、`--timeout` で変えられる）を超えたら static pod を消さずに止まる。

**Step 5**: cleanup と kubelet 復旧

```bash
porkadot --config ./porkadot.yaml install bootstrap cleanup
porkadot --config ./porkadot.yaml install kubelet --node <bootstrap-node-ip>
```

cleanup が「Bootstrap static Pods were not removed」で止まったら、表示された項目（どのマスターの
endpoint が ready でないかなど）を直してから再実行する。「Bootstrap static Pods were already removed」で
止まったら（削除後に VIP が応答しない）、Step 1 からやり直す。

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

2. MetalLB, CNI（Flannel または cnidaria）が正常に動作しているか確認

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

cleanup の前に、「クラスター再起動後に MetalLB が起動しない」の Step 4 と同じコマンドで、
`porkadot-kubernetes` の EndpointSlice に全マスターの apiserver が ready で入っていることを確かめる。

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

## drain の後に古い iSCSI セッションが残り、同じボリュームのアタッチが失敗する

### 症状

- drain したノードの `sudo iscsiadm -m session` に、もう居ない instance-manager の IP への Longhorn のセッション（`iqn.2019-10.io.longhorn:`）が残る
- そのノードに同じボリュームがアタッチされると、エンジンが `Failed to init frontend ... failed to logout target` で落ち、ボリュームが faulted になって Pod が作り直され続ける
- iscsid のログに `session N cannot be terminted because it's trying to reconnect`、logout が `32 - target likely not connected`

### 原因

Longhorn v1.11.3・v1.12.1 より前のエンジンは、起動したときの iscsid の PID を使って iscsiadm を流す。
ボリュームがアタッチされたまま iscsid が再起動すると、そのエンジンは logout ができなくなり、detach（drain を含む）のたびにセッションを残す。
残ったまま iscsid がもう一度再起動すると、そのセッションは logout もできなくなる。
porkadot 0.31 までの `install kubelet` は毎回 iscsid を再起動していた（今は `initiatorname.iscsi` が変わったときだけ）。
詳細は porkadot-dev の `docs/longhorn/iscsi-stale-sessions.md`。

### 対処

iscsid を再起動する前（drain の後、そのノードに Longhorn のボリュームがアタッチされていない状態）なら、ノードの上で logout すれば消える。

```bash
sudo iscsiadm -m session
# 残っている Longhorn のセッションごとに
sudo iscsiadm -m session -r <sid> -u
sudo iscsiadm -m node -T <iqn> -p <古い IP>:3260 -o delete
sudo iscsiadm -m session   # iscsiadm: No active sessions.
```

logout が `32` で失敗する（iscsid を再起動した後）なら、drain したまま、残ったセッションの node の記録の
`node.session.reopen_max` を 1 にして iscsid を再起動し、iscsid に諦めさせる（1 本 16 秒ほど）。
ノードの再起動でも消える。

```bash
sudo iscsiadm -m node -T <iqn> -p <古い IP>:3260 -o update -n node.session.reopen_max -v 1
sudo systemctl restart iscsid.service
sudo iscsiadm -m session   # Longhorn のセッションが消えるまで待つ
sudo iscsiadm -m node -p <古い IP>:3260 -o delete
```

---

## porkadot 実行時に SSH 接続が fingerprint mismatch で失敗する

### 症状

- porkadot 実行時に特定ノードで SSH 接続が失敗する
- エラーメッセージに `fingerprint` や `known_hosts` が含まれる

- porkadot は `Host key of <user>@<node>:22 does not match known_hosts (...)` と出す

### 原因

porkadot が使用する net-ssh (Ruby) は `~/.ssh/known_hosts` のエントリを直接検証する。
hashed の行も、同じホストの複数の行（rsa・ecdsa・ed25519）も読むので、
`ssh` で入れるのに porkadot で不一致になるなら、ノードのホスト鍵が変わった（再インストールなど）と見てよい。

porkadot 0.30.0 以前は SSHKit の known_hosts の parser を使っていて、hashed の行では最初に一致した 1 行の鍵しか見なかった。
あるノードの rsa の行が ecdsa の行より前にあると、鍵が正しくても不一致になった。

### 対処

```bash
# 登録されている鍵とノードが出す鍵を比べる
ssh-keygen -F <node-ip>
ssh-keyscan <node-ip>

# ホスト鍵が変わったと確かめてから、古いエントリを削除して入り直す
ssh-keygen -R <node-ip>
ssh <user>@<node-ip> true
```

---

## porkadot 実行時に SSH の認証で失敗する

### 症状

- `ssh` では入れるのに、porkadot は `SSH authentication failed for <user>@<node>:22 (...)` で止まる

### 原因と対処

porkadot はメッセージに、ssh-agent の状態、使う鍵、net-ssh が読めなかった鍵ファイルを出す。

- `ssh-agent: SSH_AUTH_SOCK is not set` / `not available` — ssh-agent が使えない（サンドボックスがソケットを塞いでいる場合など）。
  鍵ファイルを直接読むので、その鍵がノードに登録されていれば入れる
- `keys: ...` — `connection.keys` を書くと、その鍵ファイルしか読まない。ノードに登録されている鍵を足すか、`keys` を外して `~/.ssh/config` の `IdentityFile` と既定の鍵ファイル（`~/.ssh/id_ed25519` など）に任せる
- `net-ssh: could not load private key file ...` — その鍵ファイルを読めなかった。パスフレーズ付きの鍵は ssh-agent に載せて使う

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
- containerd と kubelet の cgroup driver が食い違っている（kubelet は `systemd`）→ `containerd config dump | grep SystemdCgroup` で runc の値が `true` か確認する。`false` なら `setup-containerd` をやり直す（→「setup-containerd が runc options セクションが無いと言って止まる」）
- kubelet の設定に誤りがある（apiserver 向き先）
- CNI（Flannel または cnidaria）が起動していない

## setup-containerd が runc options セクションが無いと言って止まる

### 症状

`porkadot setup-containerd` が `ERROR: [plugins.... .containerd.runtimes.runc.options] is not found in /etc/containerd/config.toml.` を出して失敗する。containerd は再起動されない。

### 原因

既存の `/etc/containerd/config.toml` に、runc の options セクションが無い。kubelet は cgroup driver に `systemd` を使うので、`SystemdCgroup = true` を設定できないまま続けると、containerd と cgroup driver が食い違う。そのため `setup-containerd` は止まる。

- config version 2: `[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]`
- config version 3 / 4: `[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]`

runc の options を inline table（`[...runtimes.runc]` の下の `options = { SystemdCgroup = false }`）で書いている場合も、セクションが無い扱いになる。`setup-containerd` は inline table を書き換えない。セクションのヘッダ行の末尾にコメントがあるだけなら止まらない。

### 対処

次のどちらかを行い、`setup-containerd` を再実行する。

- `/etc/containerd/config.toml` に、エラーに出たセクションを `SystemdCgroup = true` 付きで足す。inline table で書いている場合は、そのセクションの形に書き直す。
- `/etc/containerd/config.toml` を退避（例: `config.toml.porkadot-bak`）して消す。`setup-containerd` が `containerd config default` で作り直す。退避した config に独自の設定（registry mirror、NVIDIA の runtime など）があれば、作り直した config に戻す。

---

## setup-containerd が config version 4 に対応していないと言って止まる

### 症状

`porkadot setup-containerd` が `/etc/containerd/config.toml is config version 4, but containerd 2.2 does not support it (2.3 or later is required)` のようなエラーで失敗する。containerd は再起動されず、config も変わらない。

### 原因

config version 4 を読めるのは containerd 2.3 以降である。containerd 2.3 以降（Docker の `containerd.io` 2.4.2 など）で作った config が残ったまま、containerd を 2.3 未満（Ubuntu noble-updates の 2.2.1 など）に入れ替えると起きる。この組み合わせでは containerd 自体が config を読めず起動しない。

### 対処

次のどちらかを行い、`setup-containerd` を再実行する。

- containerd を 2.3 以降にする。
- `/etc/containerd/config.toml` を退避（例: `config.toml.porkadot-bak`）して消す。`setup-containerd` がいまの containerd の `containerd config default` で作り直す。退避した config に独自の設定があれば、作り直した config に戻す。

---

## `Legacy secrets layout found` で render / install が止まる

### 症状

- `porkadot render ...` や `porkadot install ...` が `Legacy secrets layout found: .../assets/secrets` で失敗する

### 原因

以前の porkadot は secret を `assets/secrets/<group>/` に出力していた。現在は `assets/<group>/` に統合されており、
旧ツリーが残っていると secret の無い asset を配布したり、CA を作り直したりする恐れがあるため止めている。

### 対処

`porkadot migrate-secrets --config ./porkadot.yaml` を実行し、続けて `render kubelet / etcd / bootstrap / kubernetes` を実行する
（`references/operations.md` の「旧レイアウト（`assets/secrets/`）からの移行」）。`render certs` は実行しない。

---

## sops の暗号化・復号に失敗する

### 症状

- `sops encrypt failed for ...` または `sops decrypt failed for ...` で render / install / set-config が止まる
- `sops command not found: sops`

### 確認ポイント

- `sops` がインストールされ PATH にあるか
- `porkadot.yaml` と同じディレクトリ（または `local.sops.config`）に `.sops.yaml` があり、`creation_rules` の `path_regex` が `assets/...` に一致するか（encrypt 失敗時）
- 復号用の鍵が使えるか（age なら `SOPS_AGE_KEY_FILE` か `~/.config/sops/age/keys.txt`）（decrypt 失敗時）
- `local.sops.enabled: false` でも、暗号化済みのファイルを読むときは復号が必要になる
