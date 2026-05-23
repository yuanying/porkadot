# 03. ConfigValidator の追加

## 目的

`porkadot render` や `porkadot install` が途中で曖昧な例外を出す前に、設定ファイルの不備を明示的に検出する。

## 背景 / 現状の問題

現在は多くの設定不備が、テンプレートrender中やSSH実行直前に `NoMethodError`、`nil` 参照、文字列処理エラーとして表面化する。

例:

- `kubernetes.control_plane_endpoint` が未指定
- `nodes` がHashでない
- `addons.enabled` に未登録addonが含まれる
- CIDR文字列が不正
- etcd member label のあるnodeが不完全

## 変更対象

- 新規 `lib/porkadot/config_validator.rb`
- `lib/porkadot.rb`
- `lib/porkadot/config.rb`
- `lib/porkadot/cmd/render.rb`
- `lib/porkadot/cmd/install.rb`
- `test/config_validator_test.rb`
- 必要に応じて `test/fixtures/config/invalid_*.yaml`

## 実装方針

`Porkadot::ConfigValidator` を追加する。

公開APIは以下にする。

```ruby
module Porkadot
  class ConfigValidator
    Error = Class.new(StandardError)

    def initialize(config)
      @config = config
    end

    def validate!
      errors = validate
      raise Error, errors.join("\n") unless errors.empty?
      true
    end

    def validate
      []
    end
  end
end
```

`Porkadot::Config` には委譲メソッドだけを追加する。

```ruby
def validate!
  Porkadot::ConfigValidator.new(self).validate!
end
```

`Config.new` の時点では検証を自動実行しない。既存テストやライブラリ利用で、部分的なconfigを読み込む互換性を保つため。

CLIでは、render/install/all の入口で `config.validate!` を呼ぶ。

最小検証項目:

- `raw.nodes` がHashである。
- `raw.kubernetes.control_plane_endpoint` が空でない文字列で、hostとportに分割できる。
- `kubernetes.networking.service_subnet` と `pod_subnet` の各CIDRが `IPAddr.new` で解釈できる。
- `addons.enabled` は配列である。
- `addons.enabled` の各要素が既知addonである。
- etcd member label の値が空でない。
- `connection.port` が整数または整数文字列である。
- `connection.user` が空でない文字列である。

エラーメッセージは設定pathを含める。

例:

```text
kubernetes.control_plane_endpoint is required
addons.enabled contains unknown addon: foo
nodes.192.168.0.10.labels.etcd.unstable.cloud/member must not be empty
```

## 互換性

- `Porkadot::Config.new` 単体では検証しない。
- CLI実行ではこれまで後段で失敗していた不正設定が、入口で失敗するようになる。
- unknown addon は明示エラーにする。これは既存の暗黙失敗よりも厳格な挙動である。

## テスト計画

`test/config_validator_test.rb` を追加する。

- 既存 valid fixture は `validate!` がtrueを返す。
- `control_plane_endpoint` 未指定でエラー。
- `nodes` がHashでない場合にエラー。
- 不正CIDRでエラー。
- unknown addonでエラー。
- empty etcd member labelでエラー。
- 複数エラーがある場合に1回の例外メッセージへ集約される。

CLI側は既存Thorテストが薄いため、このコミットでは `Config#validate!` が呼べることまでを単体テスト中心に確認する。

## 完了条件

- validatorが追加されている。
- render/install入口で `config.validate!` が呼ばれる。
- 不正設定が分かりやすいメッセージで失敗する。
- 既存テストと追加テストが通る。

## このコミットでやらないこと

- JSON Schema や外部schema gemは導入しない。
- 全設定項目の完全検証はしない。
- validatorに自動補正処理は入れない。

