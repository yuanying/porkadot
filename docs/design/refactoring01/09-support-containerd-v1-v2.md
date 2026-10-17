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
- `test/assets/setup_containerd_test.rb`（新規）
- `test/fixtures/containerd/`（新規）
- `skills/porkadot/references/operations.md`、`skills/porkadot/references/troubleshooting.md`

docs/spec の更新は `08-clean-docs-and-spec-sync` で行う。

## 実装方針

`setup-containerd.sh` は `crictl` に依存しない。

containerd の major version は node 上で実行時に判定する。major version が 1 / 2 以外なら失敗させる。

```bash
containerd_major_version() {
  containerd --version | awk '{print $3}' | sed 's/^v//' | cut -d. -f1
}
```

`/etc/containerd/config.toml` の扱いは以下の優先順位にする。

1. `${ROOT}/containerd/config.toml` がある場合は、ユーザーが明示した完全上書きとして従来通りコピーする。コピーした config の `SystemdCgroup` は書き換えない（従来の挙動と同じ）。
2. `/etc/containerd/config.toml` がすでにあり、top-level の `version` がある場合は再生成しない。
3. `/etc/containerd/config.toml` がない場合は `containerd config default` で作成する。
4. `/etc/containerd/config.toml` があっても `version` がない場合は、元のファイルを `config.toml.porkadot-bak.<YYYYmmddHHMMSS>` に退避してから `containerd config default` で作り直し、作り直したことをログに出す。

4 は Docker の `containerd.io` パッケージに対応するためである。このパッケージは `version` 行がなく `disabled_plugins = ["cri"]` だけの `/etc/containerd/config.toml` を同梱する。旧 script は毎回 `containerd config default` で作り直していたので、このノードでも通っていた。本番の worker と旧 control-plane は `containerd.io`（1.6.x）を使っているため、作り直さないと `setup-containerd` の再実行が止まる。`version` のない config は containerd 1.x では config version 1 として扱われ、CRI plugin も無効なので、残すべき設定はないと判断した。

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

どちらの path を編集するかは、containerd の major version ではなく **config の top-level `version`** で決める。編集対象は config の schema で決まるためである。

| config version | containerd 1.x | containerd 2.0〜2.2 | containerd 2.3 以降 |
|---|---|---|---|
| 2 | v1 path を編集する | v1 path を編集する（containerd 2.x は読み込み時に最新の version へ移行する） | 同左 |
| 3 | 失敗させる（containerd 1.x は読めない） | v2 path を編集する | v2 path を編集する |
| 4 | 失敗させる | 失敗させる（containerd 2.3 未満は読めない） | v2 path を編集する |
| なし | 退避して default で作り直し、作り直した config の version で上の行に従う | 同左 | 同左 |
| それ以外（5 など） | 失敗させる | 失敗させる | 失敗させる |

config version 4 の扱いは「containerd config version 4 への対応」の節に書く。

`version` のある config は、containerd の版が変わっても作り直さない。apt で containerd を 1.x から 2.x に上げたノードでは version 2 の config が残るが、v1 path に設定した `SystemdCgroup = true` は containerd 2.x の移行で v2 path に引き継がれる（containerd 2.2.1 の `config dump` で確認済み）。

runc options section がない場合は、v1 / v2 とも section を新規作成せず、script を `exit 1` で止める。containerd は再起動しない。エラーメッセージには、見つからなかった section と直し方（section を足す、または config を退避して再実行する）を書く。

- kubelet は `lib/porkadot/default.yaml` で `cgroupDriver: systemd` に固定されている。続行すると containerd は cgroupfs（`SystemdCgroup = false`）のままになり、kubelet と cgroup driver が食い違う。警告だけでは SSHKit の出力の中で見落としやすい。

- runc options section だけを追記すると、containerd の default の runc runtime が置き換わり、`runtime_type` が空になる。containerd 1.7.12 で `config dump` して確認した。
- 旧 script も、sed の追記先 section が見つからなければ何もしなかった。section を作らないことは従来の挙動の維持でもある。
- containerd 1.7.12 / 2.2.1 の `containerd config default` は、どちらも runc options section と `SystemdCgroup = false` を含む。porkadot が config を作るノードでは、この分岐に入らない。

実装は大きな TOML parser を導入せず、shell 内の限定的な処理に留める。section header は quote の種類（`"` と `'`）を区別せず、行末のコメント（`# ...`）を無視して照合する。runc の options を inline table（`[...runtimes.runc]` の下の `options = { SystemdCgroup = ... }`）で書いた config には対応しない。この形式では section が見つからない扱いになり、上のとおりエラーで止まる。inline table を書き換えるには TOML の値を解釈する必要があり、shell 内の限定的な処理の範囲を超えるためである。エラーメッセージで、section 形式に書き直すよう案内する。既存値がある場合は該当行だけを置換し、section があるが `SystemdCgroup` がない場合はその section 直下に追記する。他の runtime（`nvidia` など）の `SystemdCgroup` は変更しない。

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

## containerd config version 4 への対応

Docker の `containerd.io` 2.4.2 の `containerd config default` は `version = 4` の config を出す。当初の実装は version 4 を未知の version として止めていたため、`containerd.io` 2.4.2 のノードで setup-containerd が「Unsupported containerd config version」で失敗した。config がない場合と、`version` のない `containerd.io` 同梱の config を作り直す場合のどちらでも起きる。

containerd の公式の資料（`RELEASES.md` の Daemon Configuration、`docs/man/containerd-config.toml.5.md`）と v2.4.2 のソースで、version 4 を次のとおり確かめた。

- version 4 を読める containerd は 2.3.0 以降である。containerd 2.2.1 は version 4 の config を「expected containerd config version equal to or less than `3`, got `4`」で拒否し、起動しない（Ubuntu noble-updates の 2.2.1 で確認）。
- version 3 から 4 への移行で動くのは、top-level の `[grpc]`・`[ttrpc]`・`[debug]`・`[metrics]` を `io.containerd.server.v1.*` の plugin に移すことだけである。CRI の plugin の配置は version 3 と同じである。
- setup-containerd が触るのは runc options の `SystemdCgroup` だけである。この section は version 4 でも `[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]` で、version 3 と同じ v2 path を編集すればよい。sandbox image（`io.containerd.cri.v1.images` の `pinned_images`）、レジストリの設定（同 `registry`）、CNI の設定の場所も version 3 と変わらないが、setup-containerd はこれらを編集しない。

そこで setup-containerd は次のように扱う。

- containerd の版を major だけでなく minor まで読み取る。
- config version 4 は、containerd 2.3 以降なら v2 path を編集する。
- containerd 1.x や 2.0〜2.2 で config version 4 なら、config を変えず、containerd を再起動せずに失敗させる。メッセージには 2.3 以降が必要なことを書く。version 4 の config を書き換えて残しても、その containerd は起動できないためである。
- version 5 以降は、これまでと同じく未知の version として失敗させる。
- version 2・3 の扱いは変えない。containerd 2.3 以降のノードに残った version 2・3 の config も作り直さず、それぞれの path を編集する（containerd が読み込み時に version 4 へ移行する）。

テストには、containerd 2.4.2 の `containerd config default` の出力を fixture として加えた。実物の確認として、`containerd.io` 2.4.2 を入れた Ubuntu 24.04 のコンテナで次を確かめた。

- config がない状態から setup-containerd を実行すると version 4 の config ができ、`containerd config dump` で runc の `SystemdCgroup = true` と `runtime_type = 'io.containerd.runc.v2'` が有効になる。
- `containerd.io` 同梱の config（`version` なし、`disabled_plugins = ["cri"]`）は退避されて version 4 の default から作り直され、CRI が有効になる。
- 2 回目の実行で config が変わらない。
- containerd を起動すると、CRI の plugin（`io.containerd.cri.v1` の images・runtime と `io.containerd.grpc.v1.cri`）が `ok` で読み込まれる。

## Kubernetes version との関係

containerd v2 は Kubernetes v1.32 以降を実用上の下限として扱う。

理由:

- containerd の Kubernetes support matrix では、containerd v2.0.1+ は Kubernetes v1.32 以降の組み合わせとして示されている。
- containerd v2 は CRI v1alpha2 を持たず、CRI v1 前提である。
- porkadot の現在の default は `kubernetes.kubernetes_version: v1.29.8` なので、containerd v2 を default 前提にしない。

このコミットでは validator 連携は必須にしない。`03-add-config-validator` 実装後に、containerd v2 を明示設定する場合は Kubernetes v1.32 以上を要求する検証を追加する。

## 互換性

- `${ROOT}/containerd/config.toml` によるユーザー提供 config の優先は維持する。
- 既存 `/etc/containerd/config.toml` がある node では、無条件再生成しない。`version` のない config だけは退避してから作り直す。
- NVIDIA、gVisor、Kata、registry mirror などの既存設定を消さない。
- `setup-containerd` の CLI interface は変えない。
- containerd v1 系 node の既存挙動は、`SystemdCgroup = true` を維持する範囲で変えない。
- containerd v2 系 node では、config version 3 なら v2 の正しい config path だけを対象にする。version 2 の config が残っている node では v1 path を対象にする。
- Ubuntu の `containerd` パッケージ（noble の 1.7.12、noble-updates の 2.2.1）は `/etc/containerd/config.toml` を同梱しない。新規ノードでは porkadot が `containerd config default` で作る。

## テスト計画

render した `setup-containerd.sh` を bash で実際に実行し、生成される config を検証する。containerd バイナリが無い環境でも動くように、`containerd`（`--version` と `config default`）と `systemctl` は PATH 上の stub に置き換える。config の置き場所は、テスト専用の環境変数 `PORKADOT_CONTAINERD_CONFIG_DIR`（既定は `/etc/containerd`）で一時ディレクトリに向ける。

追加する fixture（`test/fixtures/containerd/`）:

- containerd 1.7.12 の `containerd config default` の出力（config version 2）
- containerd 2.2.1 の `containerd config default` の出力（config version 3）
- containerd 2.4.2 の `containerd config default` の出力（config version 4）
- version 4 で runc runtime section がない config
- version 2 で runc options に `SystemdCgroup` がなく、NVIDIA runtime と `imports` を含む config
- version 2 で runc options section がない config
- version 3 で runc runtime section がない config
- version 3 で NVIDIA runtime と drop-in の `imports` を含む config
- `version` がない config
- v1 / v2 それぞれ、section header の行末にコメントがある config
- version 3 で runc の options を inline table で書いた config
- Docker の `containerd.io` が同梱する config（`version` がなく `disabled_plugins = ["cri"]` だけ）

追加するテスト:

- config がない場合、v1 / v2 それぞれ default config を作り、正しい path の `SystemdCgroup` が `true` になる。
- `${ROOT}/containerd/config.toml` がある場合は、そのままコピーする。
- 既存 `/etc/containerd/config.toml` がある場合は `containerd config default` を呼ばず、`SystemdCgroup` の行以外を変えない。
- `imports` 行と、他の runtime の `SystemdCgroup` が変わらない。
- section があり `SystemdCgroup` がない場合は section 直下に追記する。
- runc options section がない場合は、v1 / v2 とも section を作らずに失敗し、containerd を再起動しない。
- runc options を inline table で書いた config も、section がない場合と同じく失敗する。
- section header の行末にコメントがあっても、v1 / v2 とも `SystemdCgroup = true` を設定する。
- containerd 2.x で version 2 の config は v1 path を編集する。
- `version` のない config（`containerd.io` 同梱のものを含む）は、v1 / v2 とも default から作り直して `SystemdCgroup = true` を設定し、元のファイルを退避する。`version` のある config は退避しない。
- containerd 2.4 で config がない場合、`containerd.io` 同梱の config を作り直す場合、既存の version 4 の config の場合は、v2 path の `SystemdCgroup` が `true` になる。既存の config は `SystemdCgroup` の行以外を変えない。
- version 4 で runc runtime section がない場合は、section を作らずに失敗する。
- containerd 2.4 で version 3 の config は v2 path を編集し、version 3 のまま残す。
- containerd 1.x で version 3・4 の config、containerd 2.2 で version 4 の config、未知の config version（5 など）、unsupported major version では失敗し、containerd を再起動しない。
- 2 回実行しても config が変わらない。

テストとは別に、containerd 1.7.12 / 2.2.1 の実バイナリで生成した config を `containerd config dump` に通し、runc の `SystemdCgroup = true` と `runtime_type = "io.containerd.runc.v2"` が有効になることを確認した。

最低限、`bundle exec rake test` が通ることを確認する。

## 完了条件

- containerd v1/v2 と config version を実行時に判定して分岐できる。
- `crictl` がない状態でも `setup-containerd` が動作する。
- 既存 `/etc/containerd/config.toml` を無条件に再生成しない（`version` のない config は退避してから作り直す）。
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
