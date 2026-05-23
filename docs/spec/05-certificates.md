# 証明書管理

## PKI 構造の概要

porkadot は 3 種類の独立した PKI を管理します。

```
assets/secrets/
├── certs/
│   ├── kubernetes/        # Kubernetes PKI
│   │   ├── ca.key / ca.crt           # Kubernetes CA
│   │   ├── apiserver.key / apiserver.crt
│   │   ├── kubelet-client.key / kubelet-client.crt
│   │   ├── admin.key / admin.crt     # kubectl 用クライアント証明書
│   │   ├── sa.key / sa.pub           # Service Account 署名鍵
│   │   └── front-proxy/              # front-proxy PKI（別 CA）
│   │       ├── ca.key / ca.crt
│   │       └── client.key / client.crt
│   └── etcd/              # etcd PKI
│       ├── ca.key / ca.crt           # etcd CA
│       ├── client.key / client.crt   # apiserver → etcd 通信用
│       └── {node}/
│           ├── etcd.key / etcd.crt   # etcd メンバー証明書
│           └── ca.crt                # （CA のコピー）
└── bootstrap/         # ブートストラップ用（secrets のコピー）
```

## 証明書の有効期限

| 証明書の種類 | 有効期限 |
|-------------|---------|
| CA 証明書 | 2 年 |
| サーバー証明書 / クライアント証明書 | 1 年 |
| ノードブートストラップ証明書 | 1 年 |

## Kubernetes PKI

### Kubernetes CA

| 項目 | 値 |
|------|-----|
| Subject | `CN=kube-ca` |
| 用途 | Kubernetes 全体の信頼アンカー |
| キー種別 | RSA 2048 |

### apiserver 証明書

| 項目 | 値 |
|------|-----|
| Subject | `CN=apiserver` |
| 用途 | kube-apiserver のサーバー証明書 |
| 拡張 | `clientAuth` + `serverAuth` |

**Subject Alternative Names（SAN）:**

以下のすべてが SAN に含まれます。

| SAN | 内容 |
|-----|------|
| コントロールプレーンエンドポイントホスト | `control_plane_endpoint` の host 部分 |
| 全マスターノードのノード名とホスト名/IP | `k8s.unstable.cloud/master` ラベルを持つ全ノード |
| Kubernetes サービス IP | service_subnet の最初の IP（例: `10.254.0.1`） |
| DNS: `kubernetes` | — |
| DNS: `kubernetes.default` | — |
| DNS: `kubernetes.default.svc` | — |
| DNS: `kubernetes.default.svc.{dns_domain}` | 例: `kubernetes.default.svc.cluster.local` |
| DNS: `porkadot-kubernetes` | — |
| DNS: `porkadot-kubernetes.kube-system` | — |
| DNS: `porkadot-kubernetes.kube-system.svc` | — |
| DNS: `porkadot-kubernetes-latest` | — |
| DNS: `porkadot-kubernetes-latest.kube-system` | — |
| DNS: `porkadot-kubernetes-latest.kube-system.svc` | — |
| DNS: `localhost` | ローカルホスト |
| IP: `127.0.0.1` | ローカルホスト |

### kubelet-client 証明書

| 項目 | 値 |
|------|-----|
| Subject | `O=system:masters / CN=kube-kubelet-client` |
| 用途 | apiserver → kubelet 通信（クライアント認証） |
| 拡張 | `clientAuth` |

### admin 証明書

| 項目 | 値 |
|------|-----|
| Subject | `O=system:masters / CN=admin` |
| 用途 | kubectl（管理者）用クライアント証明書 |
| 拡張 | `clientAuth` |

### Service Account 鍵ペア

| 項目 | 値 |
|------|-----|
| 種別 | RSA 2048 鍵ペア |
| 秘密鍵 | `sa.key`（controller-manager の署名に使用） |
| 公開鍵 | `sa.pub`（apiserver のトークン検証に使用） |

## etcd PKI

### etcd CA

| 項目 | 値 |
|------|-----|
| Subject | `CN=etcd-ca` |
| 用途 | etcd クラスタ内通信の信頼アンカー |
| キー種別 | RSA 2048 |

### etcd メンバー証明書（ノードごと）

| 項目 | 値 |
|------|-----|
| Subject | `O=porkadot:etcd-servers / CN={member_name}` |
| 用途 | etcd peer 間通信・クライアント認証 |
| 拡張 | `serverAuth` + `clientAuth` |

**Subject Alternative Names（SAN）:**

| SAN | 内容 |
|-----|------|
| DNS: `{member_name}` | etcd メンバー名（`etcd.unstable.cloud/member` ラベル値） |
| IP: `{member_address}` | etcd advertise アドレス |
| IP: `127.0.0.1` | ローカルホスト |

### etcd クライアント証明書

| 項目 | 値 |
|------|-----|
| Subject | `O=porkadot:etcd-clients / CN=kube-apiserver-etcd-client` |
| 用途 | kube-apiserver → etcd 通信（クライアント認証） |
| 拡張 | `clientAuth` |

## front-proxy PKI

### front-proxy CA

| 項目 | 値 |
|------|-----|
| Subject | `CN=front-proxy-ca` |
| 用途 | API Aggregation Layer の信頼アンカー |
| キー種別 | RSA 2048 |

### front-proxy クライアント証明書

| 項目 | 値 |
|------|-----|
| Subject | `O=porkadot:front-proxy-clients / CN=front-proxy-client` |
| 用途 | API Aggregation Layer（拡張 API へのプロキシ） |
| 拡張 | `clientAuth` |

## ノードブートストラップ証明書（ノードごと）

kubelet の TLS ブートストラップに使用する一時的な証明書です。

| 項目 | 値 |
|------|-----|
| Subject | `O=porkadot:node-bootstrappers / CN=node-bootstrapper:{node_name}` |
| 用途 | kubelet の初回 TLS ブートストラップ認証 |
| 拡張 | `clientAuth` |
| 配置先 | `/etc/kubernetes/pki/bootstrap.{key,crt}` |

kubelet はこの証明書で apiserver に接続し、正式な kubelet サービング証明書の発行リクエスト（CSR）を送信します。CSR は `kubelet-serving-cert-approver` または `kubelet-rubber-stamp` によって自動承認されます。

## 証明書のべき等性

- 秘密鍵ファイルが既に存在する場合、`render certs` は既存の鍵を再利用します
- `render certs` は証明書生成時に refresh=true を渡すため、証明書ファイルは再発行されます
- CA 証明書は一度生成したら変更しないことを推奨します（全証明書の再発行が必要になります）
