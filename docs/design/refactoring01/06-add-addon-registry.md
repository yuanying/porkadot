# 06. AddonRegistry の追加

## 目的

addonごとの manifest / secret / CRD 定義を、クラス変数ではなく明示的な registry に集約する。

未知addon名を早期に分かりやすいエラーにする。

## 背景 / 現状の問題

`lib/porkadot/assets/kubernetes.rb` の `Assets::Addons` は、`@@manifests`、`@@secrets_manifests`、`@@crds` というクラス変数にaddon定義を登録している。

この構造には次の問題がある。

- addon定義の全体像が追いにくい。
- unknown addon時に `nil.each` のような低レベル例外になりやすい。
- validatorから既知addon一覧を参照しにくい。
- テスト間でクラス変数状態が共有される。

## 変更対象

- `lib/porkadot/assets/kubernetes.rb`
- 新規 `lib/porkadot/addon_registry.rb`
- `lib/porkadot/config_validator.rb`
- `test/assets/addons_test.rb`
- `test/config_validator_test.rb`

## 実装方針

`Porkadot::AddonRegistry` を追加する。

公開API:

```ruby
module Porkadot
  class AddonRegistry
    Definition = Struct.new(:name, :manifests, :secrets, :crds, keyword_init: true)

    DEFINITIONS = {
      "flannel" => Definition.new(...),
      "coredns" => Definition.new(...),
      "metallb" => Definition.new(...),
      "kubelet-rubber-stamp" => Definition.new(...),
      "storage-version-migrator" => Definition.new(...),
      "kubelet-serving-cert-approver" => Definition.new(...),
    }.freeze

    def self.names
      DEFINITIONS.keys
    end

    def self.fetch(name)
      DEFINITIONS.fetch(name) do
        raise KeyError, "unknown addon: #{name}"
      end
    end
  end
end
```

`Assets::Addons#render` は以下のように変更する。

```ruby
config.enabled.each do |name|
  addon = Porkadot::AddonRegistry.fetch(name)
  addon.manifests.each { |m| render_erb(m) }
  addon.secrets.each { |m| render_secrets_erb(m) }
  addon.crds.each { |m| copy_crds(m) }
end
```

`ConfigValidator` は `AddonRegistry.names` を使って unknown addon を検出する。

既存の `register_manifests` は削除する。外部plugin APIとして公開されていないため、互換維持対象にしない。

## 互換性

- `addons.enabled` に指定できる既存addon名は変えない。
- enabledの順序は出力順序として維持する。
- unknown addonは低レベル例外ではなく、validatorまたはregistryの明示エラーになる。

## テスト計画

`test/assets/addons_test.rb` に以下を追加する。

- `AddonRegistry.names` が既存addon名を含む。
- `AddonRegistry.fetch("flannel")` がmanifest一覧を返す。
- unknown addonで `KeyError` と分かりやすいメッセージ。
- `Assets::Addons#render` が `addons.enabled` の順にrenderする。

`test/config_validator_test.rb` に unknown addon の検証を追加する。

## 完了条件

- addon定義が `AddonRegistry` に集約されている。
- `Assets::Addons` からクラス変数登録がなくなっている。
- validatorがregistryを参照している。
- 既存テストと追加テストが通る。

## このコミットでやらないこと

- addon plugin機構は作らない。
- addon manifestの内容は変更しない。
- addon有効化の設定形式は変更しない。

