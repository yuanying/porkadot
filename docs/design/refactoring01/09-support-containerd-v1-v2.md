# 09. containerd v1/v2 両対応

## 目的

`porkadot setup-containerd` が containerd v1 系と v2 系の両方で安全に動くようにする。

特に、既存の `/etc/containerd/config.toml` を無条件に再生成して、NVIDIA Container Toolkit など別プロセスが追加した runtime / imports / drop-in 設定を壊さないことを優先する。

## 背景 / 現状の問題

対象は `lib/porkadot/assets/kubelet-default/setup-containerd.sh.erb`。

現在の script は次の流れになっている。

1. `/etc/containerd` を作成する。
2. `${ROOT}/containerd/config.toml` があれば `/etc/containerd/config.toml` にコピーする。
3. なければ `containerd config default` を `/etc/containerd/config.toml` に出力する。
4. `SystemdCgroup = true` を sed で設定する。
5. containerd を再起動する。

この構造には次の問題がある。

- containerd v1 と v2 で CRI plugin の設定 path が違う。
- v2 の config version 3 では、v1 用の path へ `SystemdCgroup` を追加しても意図した設定にならない。
- 既存 config がある node でも `containerd config default` で上書きし得る。
- NVIDIA Container Toolkit は `/etc/containerd/config.toml` の `imports` を更新し、`/etc/containerd/conf.d/99-nvidia.toml` のような drop-in を作るため、無条件再生成は危険である。
- `setup-containerd` は `install-deps.sh` より前に実行されるため、この段階では `/opt/bin/crictl` が存在しない可能性が高い。

## 変更対象

- `lib/porkadot/assets/kubelet-default/setup-containerd.sh.erb`
- `test/assets/kubelet_test.rb` または新規 `test/assets/kubelet_default_test.rb`
- 必要に応じて `test/fixtures/`

docs/spec の更新は `08-clean-docs-and-spec-sync` で行う。

## 実装方針

`setup-containerd.sh` は `crictl` に依存しない。

containerd の major version は node 上で実行時に判定する。

```bash
containerd_major_version() {
  containerd --version | awk '{print $3}' | sed 's/^v//' | cut -d. -f1
}
```

`/etc/containerd/config.toml` の扱いは以下の優先順位にする。

1. `${ROOT}/containerd/config.toml` がある場合は、ユーザーが明示した完全上書きとして従来通りコピーする。
2. `/etc/containerd/config.toml` がすでにある場合は再生成しない。
3. `/etc/containerd/config.toml` がない場合のみ `containerd config default` で作成する。

```bash
ensure_containerd_config() {
  mkdir -p /etc/containerd

  if [[ -f ${ROOT}/containerd/config.toml ]]; then
    cp -rp "${ROOT}/containerd/config.toml" /etc/containerd/config.toml
    return
  fi

  if [[ ! -f /etc/containerd/config.toml ]]; then
    containerd config default > /etc/containerd/config.toml
  fi
}
```

`SystemdCgroup = true` は kubelet の `cgroupDriver: systemd` と揃えるために必要な場合だけ設定する。

containerd v1 の path:

```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
  SystemdCgroup = true
```

containerd v2 の path:

```toml
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
  SystemdCgroup = true
```

v2 では、runc runtime class が明示されていない場合 containerd の auto-detection に任せる。つまり、v2 config に v2 の runc runtime section が存在しない場合は、`SystemdCgroup` を無理に追記しない。

v1 では、従来と同じく runc options section がなければ追記する。これは既存の porkadot の挙動を維持するためである。

実装は大きな TOML parser を導入せず、shell 内の限定的な処理に留める。既存値がある場合は該当行だけを置換し、section があるが `SystemdCgroup` がない場合はその section 直下に追記する。

unsupported major version は明示的に失敗させる。

```bash
case "$(containerd_major_version)" in
  1)
    configure_systemd_cgroup_v1
    ;;
  2)
    configure_systemd_cgroup_v2
    ;;
  *)
    echo "Unsupported containerd major version: $(containerd --version)" >&2
    exit 1
    ;;
esac
```

## Kubernetes version との関係

containerd v2 は Kubernetes v1.32 以降を実用上の下限として扱う。

理由:

- containerd の Kubernetes support matrix では、containerd v2.0.1+ は Kubernetes v1.32 以降の組み合わせとして示されている。
- containerd v2 は CRI v1alpha2 を持たず、CRI v1 前提である。
- porkadot の現在の default は `kubernetes.kubernetes_version: v1.29.8` なので、containerd v2 を default 前提にしない。

このコミットでは validator 連携は必須にしない。`03-add-config-validator` 実装後に、containerd v2 を明示設定する場合は Kubernetes v1.32 以上を要求する検証を追加する。

## 互換性

- `${ROOT}/containerd/config.toml` によるユーザー提供 config の優先は維持する。
- 既存 `/etc/containerd/config.toml` がある node では、無条件再生成しない。
- NVIDIA、gVisor、Kata、registry mirror などの既存設定を消さない。
- `setup-containerd` の CLI interface は変えない。
- containerd v1 系 node の既存挙動は、`SystemdCgroup = true` を維持する範囲で変えない。
- containerd v2 系 node では、v2 の正しい config path だけを対象にする。

## テスト計画

script そのものを直接実行しやすくするため、生成済み script に対する fixture ベースのテストを追加する。

追加する fixture:

- containerd v1 config
- containerd v2 config with runc runtime section
- containerd v2 config without runc runtime section
- imports を含む config
- NVIDIA drop-in を想定した `imports = ["/etc/containerd/conf.d/*.toml"]` を含む config

追加するテスト:

- `${ROOT}/containerd/config.toml` がある場合はコピー優先の分岐が残っている。
- 既存 `/etc/containerd/config.toml` がある場合は `containerd config default` で上書きしない。
- v1 config では v1 path の `SystemdCgroup = true` が設定される。
- v2 config では v2 path の `SystemdCgroup = true` が設定される。
- v2 config に runc runtime section がない場合は `SystemdCgroup` section を新規作成しない。
- `imports` 行が削除されない。
- unsupported major version では script が失敗する。

最低限、`bundle exec rake test` が通ることを確認する。

## 完了条件

- containerd v1/v2 を実行時に判定して分岐できる。
- `crictl` がない状態でも `setup-containerd` が動作する。
- 既存 `/etc/containerd/config.toml` を無条件に再生成しない。
- v1/v2 それぞれの正しい path で `SystemdCgroup` を扱う。
- containerd v2 で不要な config section を勝手に作らない。
- NVIDIA などの外部 runtime 設定を壊さない方針がテストで確認されている。

## このコミットでやらないこと

- containerd パッケージのインストール方法は変更しない。
- `setup-node` / `install kubelet` の実行順序は変更しない。
- `crictl` のインストール順序は変更しない。
- TOML parser gem は導入しない。
- containerd v2 を default にしない。
- validator への Kubernetes version guard 実装は後続作業にする。
