# 04. 暗黙的Configアクセスの段階的置換

## 目的

`ConfigUtils#method_missing` による `raw` への暗黙アクセスを減らし、主要な設定値を明示アクセサとして定義する。

このコミットでは互換性維持のため `method_missing` は削除しない。
`Hashie::Mash` と `method_missing` の完全撤廃は、後続の
`10-remove-hashie-and-method-missing.md` で扱う。

## 背景 / 現状の問題

`lib/porkadot/config.rb` の `ConfigUtils#method_missing` は、存在しないメソッドを `raw[name]` に委譲している。

この仕組みはテンプレートや設定クラスを短く書ける一方で、次の問題がある。

- typo が実行時まで検出されない。
- どの設定値がpublic interfaceなのか分かりにくい。
- `respond_to?` と実際の利用可能値が直感的でない。
- validatorやテストで対象フィールドを特定しにくい。

## 変更対象

- `lib/porkadot/config.rb`
- `lib/porkadot/configs/*.rb`
- `test/configs/*_test.rb`
- 必要に応じてERBテンプレート

## 実装方針

利用頻度が高く、テンプレートや他クラスから参照される主要設定だけを明示アクセサへ移す。

最初の対象:

- `Configs::Kubernetes`
  - `cluster_name`
  - `control_plane_endpoint`
  - `kubernetes_version`
  - `crictl_version`
  - `image_repository`
  - `log_level`
- `Configs::Kubernetes::Networking`
  - `service_subnet`
  - `pod_subnet`
  - `dns_domain`
  - `additional_domains`
  - `cni_version`
- `Configs::Kubernetes::Apiserver`
  - `bind_port`
  - `extra_args`
  - `log_level`
- `Configs::Kubernetes::Scheduler`
  - `extra_args`
  - `log_level`
- `Configs::Kubernetes::ControllerManager`
  - `extra_args`
  - `log_level`
- `Configs::Etcd`
  - `image_repository`
  - `image_tag`
  - `extra_env`
- `Configs::Kubelet`
  - `labels`
  - `annotations`
  - `taints`
  - `hostname`

アクセサ実装は、既存のdefault merge済み `raw` から値を返すだけにする。

例:

```ruby
def control_plane_endpoint
  raw.control_plane_endpoint
end
```

既存のメソッド名と衝突する場合は、既存メソッドを優先し、その中で明示的に `raw` を参照する。

`ConfigUtils#method_missing` には非推奨コメントを追加する。ただしwarnは出さない。テンプレートrender中に大量の警告が出るため。

## 互換性

- `method_missing` は残すため、既存テンプレートの多くは変更不要。
- public methodが増えるだけなので、通常利用者への破壊的変更はない。
- typo検出の完全化はこのコミットでは達成しない。

## テスト計画

既存 `test/configs/*_test.rb` に主要アクセサの期待値を追加する。

- `config.k8s.control_plane_endpoint` がfixture値を返す。
- `config.k8s.networking.service_subnet` がdefault merge後の値を返す。
- `config.etcd.image_repository` がdefault値を返す。
- `config.nodes[name].hostname` がnode設定またはnameを返す。

既存renderテストを実行し、テンプレート互換性を確認する。

## 完了条件

- 主要設定値に明示アクセサがある。
- 既存テンプレートとテストが通る。
- `ConfigUtils#method_missing` には互換用であることがコメントされている。

## このコミットでやらないこと

- `method_missing` の削除はしない。
- 全設定項目のアクセサ化はしない。
- typed struct やdry-types等の導入はしない。
- `Hashie::Mash` 依存の完全撤廃はしない。
