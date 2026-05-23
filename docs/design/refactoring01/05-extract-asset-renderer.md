# 05. Asset Renderer の切り出し

## 目的

ERBテンプレートの読み込み、出力先ディレクトリ作成、通常ファイル/secretファイルの書き込みを `Renderer` に集約する。

Assets各クラスは「何をrenderするか」を表し、Rendererは「どうrenderするか」を担当する構造にする。

## 背景 / 現状の問題

`lib/porkadot/assets.rb` の `render_erb` と `render_secrets_erb` は多くの処理を重複して持っている。

また、テンプレート変数の組み立て、出力パス解決、skip条件、ファイル作成が同じメソッドに混在している。

そのため次の変更が難しい。

- render結果のテスト
- secret出力の一貫した扱い
- addon CRD copyとの共通化
- overwrite/skip条件の整理

## 変更対象

- `lib/porkadot/assets.rb`
- 新規 `lib/porkadot/assets/renderer.rb`
- `lib/porkadot/assets/*.rb`
- `test/assets/*_test.rb`

## 実装方針

`Porkadot::Assets::Renderer` を追加する。

公開API:

```ruby
module Porkadot
  module Assets
    class Renderer
      def initialize(template_dir:, config:, global_config:, logger:)
      end

      def render_template(file, destination:, overwrite: true, vars: {})
      end

      def copy_file(file, destination:, overwrite: true)
      end
    end
  end
end
```

`render_template` は次を行う。

1. `template_dir/#{file}.erb` を読む。
2. 既存テンプレート互換の変数を組み立てる。
3. `destination` の親ディレクトリを作る。
4. `overwrite: false` かつ既存ファイルがある場合はskipする。
5. ERBを評価して書き込む。

テンプレート変数は既存互換を維持する。

- `config`
- `global_config`
- `certs`
- `u`
- 呼び出し側から渡された追加vars

既存の `render_erb` / `render_secrets_erb` は互換メソッドとして残し、内部でRendererを呼ぶ。

`render_erb(file, force: false)` の既存挙動は分かりにくい。互換維持のため、このコミットでは呼び出し側の挙動を変えず、内部で `overwrite` に変換する。

変換ルール:

- `force` が `nil` の場合は上書きする。
- `force` が `false` の場合は既存ファイルがあればskipする。
- `force` が `true` の場合は上書きする。

このルールをテストで固定する。

## 互換性

- 出力ファイルパスは変えない。
- テンプレート内で使える変数名は変えない。
- `render_erb` / `render_secrets_erb` は削除しない。

## テスト計画

`test/assets/renderer_test.rb` を追加する。

- 通常テンプレートを指定destinationに出力できる。
- secret相当のdestinationにも同じAPIで出力できる。
- 親ディレクトリが自動作成される。
- `overwrite: false` で既存ファイルを保持する。
- 追加varsがテンプレートへ渡る。

既存 assets tests を実行し、render結果が変わらないことを確認する。

## 完了条件

- Rendererが追加されている。
- 既存Assetsクラスは互換メソッド経由または直接Renderer経由で動く。
- 重複していたERB書き込み処理が一箇所に集約されている。
- 既存テストと追加テストが通る。

## このコミットでやらないこと

- テンプレートの内容変更はしない。
- render対象ファイル一覧の再設計はしない。
- addon registry化は次コミットで行う。

