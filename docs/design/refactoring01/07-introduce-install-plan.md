# 07. InstallPlan の導入

## 目的

SSHKitで実行する前に、install処理の操作列をデータとして表現できるようにする。

まず `porkadot install kubernetes` に導入し、dry-runで何が実行されるか確認できる状態にする。

## 背景 / 現状の問題

`lib/porkadot/install/kubernetes.rb` は、upload、mkdir、rm、bash実行をSSHKit DSL内に直接書いている。

この構造には次の問題がある。

- 実SSHなしでinstall手順をテストしにくい。
- dry-runができない。
- upload元/先、環境変数、実行順序がコードを読まないと分からない。
- bootstrap/kubeletへ同じ考え方を広げにくい。

## 変更対象

- 新規 `lib/porkadot/install/plan.rb`
- `lib/porkadot/install/kubernetes.rb`
- `lib/porkadot/cmd/install/kubernetes.rb`
- `test/install/kubernetes_test.rb`

## 実装方針

`Porkadot::Install::Plan` を追加する。

操作は小さい構造体で表す。

```ruby
module Porkadot
  module Install
    class Plan
      Operation = Struct.new(:type, :args, :env, keyword_init: true)

      attr_reader :host, :operations

      def initialize(host:)
        @host = host
        @operations = []
      end

      def mkdir(path)
      end

      def rm_rf(path)
      end

      def upload(source, destination, recursive: false)
      end

      def execute(*command, env: {})
      end

      def to_s
      end
    end
  end
end
```

`Install::Kubernetes` に `build_plan(host, target: "")` を追加する。

生成する操作列は既存installと同じ順序にする。

1. `mkdir -p ./kube_temp`
2. 既存 `./kube_temp/kubernetes` がある場合の削除
3. 既存 `./kube_temp/.kubernetes` がある場合の削除
4. `config.target_path` を `./kube_temp/kubernetes` へupload
5. `config.target_secrets_path` を `./kube_temp/.kubernetes` へupload
6. `KUBE_TARGET` と `KUBECONFIG` 付きで `install.secrets.sh` を実行
7. 同じenvで `install.sh` を実行し、capture結果をinfoへ流す

条件付き削除は `test` + `rm_rf` のような操作として表現する。

例:

```ruby
plan.rm_rf_if_dir(KUBE_TEMP)
```

SSHKit実行用に `execute_plan(plan)` を追加する。既存 `install(host, target="")` は `build_plan` して `execute_plan` するだけにする。

CLIに `--dry-run` を追加する。

`--dry-run` の場合:

- SSH接続しない。
- `build_plan` の `to_s` を標準出力へ出す。
- exit statusは成功にする。

## 互換性

- `--dry-run` 未指定時のinstall挙動は変えない。
- まずkubernetes installだけ対象にする。
- kubelet/bootstrap installへの展開は後続作業とする。

## テスト計画

`test/install/kubernetes_test.rb` に以下を追加する。

- `build_plan` が期待hostを保持する。
- upload元が `config.kubernetes.target_path` と `target_secrets_path` である。
- upload先が既存定数と一致する。
- `install.secrets.sh` が `install.sh` より先に実行される。
- `KUBE_TARGET` と `KUBECONFIG` がexecute操作に含まれる。
- `to_s` にhost、upload、executeが読みやすく含まれる。

CLI dry-runはThorテスト基盤が薄いため、最低限 `Install::Kubernetes#build_plan` の単体テストを優先する。CLIテストを追加できる場合は、`--dry-run` でSSHKitが呼ばれないことを確認する。

## 完了条件

- kubernetes installの操作列を `Install::Plan` として生成できる。
- `porkadot install kubernetes --dry-run` で計画を表示できる。
- 通常installの既存挙動が維持されている。
- 既存テストと追加テストが通る。

## このコミットでやらないこと

- kubelet/bootstrap installのplan化はしない。
- SSHKitの全面置換はしない。
- リモート状態検出や差分適用はしない。

