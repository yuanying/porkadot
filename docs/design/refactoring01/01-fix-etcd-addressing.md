# 01. etcd アドレス解決バグの修正

## 目的

etcd node の listen address / peer address 解決にある既知バグを、小さい独立コミットで修正する。

このコミットでは設計整理よりも、現在の挙動バグの修正を優先する。

## 背景 / 現状の問題

対象は `lib/porkadot/configs/etcd.rb` と `lib/porkadot/const.rb`。

現在は次の問題がある。

- `EtcdNode#listen_address` 内で `listen_adress` という typo を参照しているため、label で指定した listen address が正しく扱われない。
- `ETCD_LISTEN_PEER_ADDRESS_LABEL` が `etcd.unstable.cloud/listen-client-address` と同じ値になっている。
- `EtcdNode#listen_peer_urls` が `listen_peer_address` ではなく `listen_client_address` を使っている。
- docs/spec ではこの不整合が「現状実装値」として記載されており、実装修正後に更新が必要になる。

## 変更対象

- `lib/porkadot/const.rb`
- `lib/porkadot/configs/etcd.rb`
- `test/configs/etcd_test.rb`

docs/spec の更新は `08-clean-docs-and-spec-sync` で行う。

## 実装方針

`ETCD_LISTEN_PEER_ADDRESS_LABEL` を新しい正しい値に変更する。

```ruby
ETCD_LISTEN_PEER_ADDRESS_LABEL = "etcd.unstable.cloud/listen-peer-address"
```

互換性のため、古い誤定義の値も fallback として扱う。定数名は新設する。

```ruby
ETCD_LEGACY_LISTEN_PEER_ADDRESS_LABEL = "etcd.unstable.cloud/listen-client-address"
```

`EtcdNode#listen_address(label_key)` は以下の優先順位にする。

1. `raw.labels[label_key]`
2. peer address 解決時のみ `raw.labels[ETCD_LEGACY_LISTEN_PEER_ADDRESS_LABEL]`
3. `raw.labels[ETCD_LISTEN_ADDRESS_LABEL]`
4. `raw.hostname` が IP address なら `raw.hostname`
5. node name が IP address なら `name`
6. `0.0.0.0`

`raw.name` は使わない。node name は `EtcdNode#name` を使う。

`listen_peer_urls` は必ず `listen_peer_address` を使う。

```ruby
def listen_peer_urls
  ["https://#{self.listen_peer_address}:2380"]
end
```

`listen_client_urls` と `listen_metrics_urls` の localhost 追加条件は既存挙動を維持する。

## 互換性

- 新しい peer label は `etcd.unstable.cloud/listen-peer-address` とする。
- 既存の誤った peer label 利用者向けに、`listen-client-address` は peer address fallback として残す。
- ただし、新labelと旧labelが両方ある場合は新labelを優先する。

## テスト計画

`test/configs/etcd_test.rb` に以下を追加する。

- `listen_client_address` は `listen-client-address` を優先する。
- `listen_peer_address` は `listen-peer-address` を優先する。
- `listen_peer_address` は新labelがない場合のみ legacy label を fallback する。
- `listen_address` は個別labelがない場合 `listen-address` に fallback する。
- hostname が IP の場合は hostname を使う。
- node name が IP の場合は node name を使う。
- hostname/node name がIPでない場合は `0.0.0.0` を使う。
- `listen_peer_urls` が peer address と port 2380 を使う。

## 完了条件

- typo がなくなっている。
- peer address と client address の解決が分離されている。
- 既存テストと追加テストが通る。

## このコミットでやらないこと

- docs/spec の更新はしない。
- etcd manifest template の構造変更はしない。
- 設定validatorの追加はしない。

