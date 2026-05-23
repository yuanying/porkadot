# 02. 設定派生メソッドの可変Raw排除

## 目的

設定オブジェクトから派生値を作るメソッドが、元の `raw` 設定を変更しないようにする。

同じ `Porkadot::Config` インスタンスで複数回 render しても、設定値が重複・汚染されないことを保証する。

## 背景 / 現状の問題

`lib/porkadot/configs/kubelet.rb` の `Kubelet#kubelet_config` は、node固有設定または共通 kubelet 設定由来の `Hashie::Mash` を操作している。

特に次の処理は元の設定を変更する可能性がある。

- `kc.clusterDNS << config.k8s.networking.dns_ip.to_s`
- `kc.clusterDomain = ...`
- `kc.registerWithTaints = ...`

`lib/porkadot/configs/kubernetes.rb` の `Proxy#proxy_config` も同様に、`raw.config` へ直接 `clusterCIDR` と `clientConnection.kubeconfig` を書き込んでいる。

## 変更対象

- `lib/porkadot/configs/kubelet.rb`
- `lib/porkadot/configs/kubernetes.rb`
- `test/configs/kubelet_test.rb`
- `test/configs/kubernetes_test.rb`

## 実装方針

設定派生メソッドでは、元の `raw` を直接変更しない。

共通方針は次の通り。

- `to_hash` で通常Hashへ変換する。
- 再帰mergeが必要な場合は既存の `rmerge` を使う。
- 返却用に `Porkadot::Raw.new(...)` を作る。
- 配列は共有しないように `dup` またはMarshal/YAML経由でdeep copyする。

`Kubelet#kubelet_config` は以下の構造にする。

```ruby
base = config.kubernetes.kubelet.config.to_hash
node = raw.config ? raw.config.to_hash : {}
kc = Porkadot::Raw.new(base.rmerge(node))
kc.clusterDNS = Array(kc.clusterDNS).dup
kc.clusterDNS << config.k8s.networking.dns_ip.to_s unless kc.clusterDNS.include?(...)
kc.clusterDomain = config.k8s.networking.dns_domain
kc.registerWithTaints = raw.taints if raw.taints
kc
```

merge優先順位は「共通設定をnode設定で上書き」とする。現在のコードが意図していた挙動と異なる場合は、テストで期待値を明示してから実装する。

`Proxy#proxy_config(kubeconfig=nil)` は以下の構造にする。

```ruby
proxy_config = Porkadot::Raw.new(raw.config.to_hash)
proxy_config["clusterCIDR"] = config.k8s.networking.pod_subnet
if kubeconfig
  proxy_config["clientConnection"] ||= {}
  proxy_config["clientConnection"]["kubeconfig"] = kubeconfig
end
proxy_config.to_hash.to_yaml
```

## 互換性

- render結果は変えない。
- 変更するのは内部状態の扱いだけ。
- `Kubelet#kubelet_config` のmerge優先順位は、既存テストとfixtureを確認して固定する。

## テスト計画

`test/configs/kubelet_test.rb` に以下を追加する。

- `kubelet_config` を2回呼んでも `clusterDNS` が重複しない。
- node固有configが共通configを上書きできる。
- `registerWithTaints` がnodeにtaintsがある場合だけ設定される。

`test/configs/kubernetes_test.rb` に以下を追加する。

- `proxy_config` 呼び出し後も `config.k8s.proxy.raw.config` に `clusterCIDR` が残らない。
- kubeconfig引数ありで返却YAMLだけが上書きされる。
- kubeconfig引数なしで既存のデフォルト kubeconfig が維持される。

## 完了条件

- 派生メソッド呼び出しによる `raw` 変更がなくなる。
- 同一Configで複数回呼び出しても返却値が安定する。
- 既存テストと追加テストが通る。

## このコミットでやらないこと

- `Hashie::Mash` の全面撤廃はしない。
- `method_missing` の削除はしない。
- validator追加はしない。

