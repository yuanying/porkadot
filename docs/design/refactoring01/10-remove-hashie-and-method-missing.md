# 10. Hashie / method_missing 依存の完全撤廃

## 目的

`Hashie::Mash` と `ConfigUtils#method_missing` への依存を完全に削除し、load 時点で YAML を明示フィールドを持つ `Porkadot::Config::XXX` オブジェクトへ変換する。

`04-replace-implicit-config-access.md` は互換性を維持しながら主要設定値の明示アクセサを追加する準備フェーズである。この設計では、その後続として `raw` そのものを維持せず、設定値を constructor で各 config object の instance variable に格納する。

最終状態では、設定参照は `config.k8s.control_plane_endpoint` や `config.nodes[name].hostname` のような明示 reader だけになる。未定義フィールドは通常の Ruby メソッド呼び出しとして `NoMethodError` になる。

## 背景 / 現状の問題

現在の config は `Porkadot::Raw < Hashie::Mash` に YAML と default の merge 結果を格納し、各 config wrapper が `raw` を参照している。

さらに `ConfigUtils#method_missing` が未定義メソッドを `raw[name]` に委譲するため、次の依存が残る。

- 設定値の typo が `nil` として扱われやすい。
- config object の public interface がコード上で明確にならない。
- `Hashie::Mash#to_hash`、dot access、代入 API に実装が引きずられる。
- ERB binding でも `Hashie::Mash.new({obj: obj})` による暗黙アクセスが使われている。
- `raw` 直接参照が config / install / test に残り、load 後の config object が typed な状態になっていない。

## 変更対象

- `lib/porkadot/config.rb`
- `lib/porkadot/configs/*.rb`
- `lib/porkadot/assets.rb`
- `lib/porkadot/install/*.rb`
- `lib/porkadot/assets/**/*.erb`
- `test/configs/*_test.rb`
- `test/install/*_test.rb`
- `porkadot.gemspec`

## 実装方針

実装は次の順序で行う。

1. `rg "Hashie|Porkadot::Raw|method_missing|respond_to_missing|\\.raw\\." lib test` で依存箇所を棚卸しする。
2. `Porkadot::Config` 配下のオブジェクト構造を定義し、各 class が `attr_reader` で明示フィールドを持つようにする。
3. load 時に default merge 済み Hash を `Porkadot::Config::Kubernetes`、`Porkadot::Config::Etcd`、`Porkadot::Config::Kubelet` などへ完全変換する。
4. config wrapper 外からの `raw` 参照を明示 reader へ置換する。
5. `Porkadot::Raw.new(...).to_hash` 前提の処理を、明示 config object から plain Hash を組み立てる処理に置換する。
6. ERB binding の `Hashie::Mash.new({obj: obj})` を Hashie なしの明示 binding に置換する。
7. `ConfigUtils#method_missing` と `respond_to_missing?` を削除する。
8. `Porkadot::Raw`、`Config#raw`、`raw` reader、`require 'hashie'`、gemspec の `hashie` 依存を削除する。

YAML 由来の Hash は load / merge / object construction の入力としてだけ扱う。constructed config object には `raw` や source Hash を保持しない。

既存の `config.k8s.control_plane_endpoint`、`config.etcd.image_repository`、`config.nodes[name].hostname` のような明示 API は維持する。外部 CLI 挙動と render 生成物は変更しない。

## 詳細

### Config object construction

`Config#initialize` は default config と user config を plain Hash として読み込み、deep merge した後、直ちに明示 config object へ変換する。

`Config` 自身は次の reader を持つ。

- `connection`
- `addons`
- `bootstrap`
- `kubernetes`
- `k8s`
- `etcd`
- `kubelet_default`
- `nodes`
- `etcd_nodes`

各 reader は Hash ではなく、対応する config object または config object の Hash を返す。`nodes` は node name を key、`Porkadot::Config::Kubelet` 相当の object を value にする。

`Config#raw` は削除する。load 後に default merge 済み Hash を保持する escape hatch は作らない。

### Explicit config classes

既存の `Porkadot::Configs::*` は、`raw` を包む wrapper ではなく、`Porkadot::Config::XXX` 配下の明示フィールドを持つ config class に置き換える。移行後は `Porkadot::Configs` 名前空間を残さない。

各 class は constructor で必要な値を受け取り、`attr_reader` で公開する。

例:

```ruby
class Porkadot::Config
  class Kubernetes
    attr_reader :cluster_name,
                :control_plane_endpoint,
                :kubernetes_version,
                :crictl_version,
                :image_repository,
                :log_level,
                :networking,
                :proxy,
                :apiserver,
                :controller_manager,
                :scheduler

    def initialize(values, config:)
      @config = config
      @cluster_name = values.fetch('cluster_name', 'porkadot')
      @control_plane_endpoint = values.fetch('control_plane_endpoint')
      @kubernetes_version = values.fetch('kubernetes_version')
      @crictl_version = values.fetch('crictl_version')
      @image_repository = values.fetch('image_repository')
      @log_level = values['log_level']
      @networking = Networking.new(values.fetch('networking'), config: config)
      @proxy = Proxy.new(values.fetch('proxy'), config: config)
      @apiserver = Apiserver.new(values.fetch('apiserver'), config: config)
      @controller_manager = ControllerManager.new(values.fetch('controller_manager'), config: config)
      @scheduler = Scheduler.new(values.fetch('scheduler'), config: config)
    end
  end
end
```

constructor の入力 Hash は validation / construction 用の一時値としてのみ使う。`@raw` や `@values` として保持しない。

optional な値は `values['key']` で受け取り、required な値は `fetch` で欠落を即時に検出する。エラーメッセージを整える必要がある場合は、既存 validator または construction helper で扱う。

### Hash-valued fields

`labels`、`annotations`、`extra_args`、`extra_env`、kubelet config、kube-proxy config のように Hash や Array として意味を持つ値は、field として保持してよい。

ただし、Hashie の dot access は提供しない。返す値は plain Hash / Array とし、内部状態を守る必要がある箇所では copy を返す。

kubelet / kube-proxy の派生 config 生成では、保持している field から plain Hash を組み立てる。

### ConfigUtils

`ConfigUtils` は path helper と `config` / `logger` helper だけにする。

`raw` reader、`method_missing`、`respond_to_missing?` は削除する。`raw` を互換 alias として残さない。

### ERB rendering

`lib/porkadot/assets.rb` の ERB binding は Hashie を使わず、明示的な binding object か renderer instance の binding を使う。

テンプレート内で参照される `config`、`global_config`、`k8s`、`etcd`、`node`、`certs` などは、既存と同じ名前で使えるようにする。テンプレートの大きな書き換えは避ける。

### Install layer

install layer で `config.raw.labels` のように node raw を参照している箇所は、`config.labels` や `config.etcd_member?` のような明示メソッドに置換する。

SSHKit の実行順序やアップロード対象は変更しない。

## 互換性

- `porkadot.yaml` の形式は変更しない。
- CLI のコマンド名、オプション、生成ファイルパスは変更しない。
- render 生成物は、Hashie 依存除去による順序差分を除き変更しない。
- config object の暗黙メソッド呼び出しは内部互換対象外とし、明示 API だけを維持する。
- `Config#raw` と各 config object の `raw` は内部互換対象外として削除する。

## テスト計画

- `bundle exec rake test`
- config tests で、default と user config が load 時に明示 config object へ変換されることを確認する。
- config tests で、主要 config object が明示 reader を持ち、`raw` に応答しないことを確認する。
- kubelet / kube-proxy の派生 config が明示 field から既存と同じ YAML を生成することを確認する。
- render tests で、主要生成物の内容が撤廃前後で変わらないことを確認する。
- install tests で、node label 判定が `raw` なしで既存どおり動くことを確認する。
- `rg "Hashie|Porkadot::Raw|method_missing|respond_to_missing|def raw|attr_reader :raw" lib test porkadot.gemspec` がヒットしないことを確認する。

## 完了条件

- `Hashie::Mash` を実装コードで使っていない。
- `Porkadot::Raw` が削除されている。
- load 後の config は明示フィールドを持つ `Porkadot::Config::XXX` オブジェクトで構成されている。
- `ConfigUtils#method_missing` と `respond_to_missing?` が削除されている。
- `Config#raw` と config object の `raw` reader が存在しない。
- `hashie` gem 依存が削除されている。
- 既存テストが通る。

## このコミットでやらないこと

- `porkadot.yaml` の schema 変更はしない。
- dry-types、dry-schema、ActiveModel などの typed schema ライブラリは導入しない。
- config class の全面的な namespace 再設計はしない。
- install plan や asset renderer の機能追加はしない。
