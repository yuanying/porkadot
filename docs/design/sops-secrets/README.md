# secret の統合と sops による暗号化

## 目的

porkadot が生成する secret（証明書・秘密鍵・kubeconfig・secret マニフェスト・`install.secrets.sh` など）を、ローカルでは sops で暗号化した状態で扱えるようにする。暗号化した assets は git で管理できる。リモートへ転送するときにだけメモリ上で復号し、ノードには従来と同じ内容を届ける。

あわせて、secret を通常の asset と別ツリーで扱う構造をやめ、render と upload の経路を一本にする。

## 背景 / 従来の問題

従来の porkadot は secret を `assets/secrets/<group>/...` に平文で出力し、通常の asset（`assets/<group>/...`）とは別ツリーで扱っていた。

- render: 通常の asset は `render_erb`、secret は `render_secrets_erb` で出力していた。設定クラスには `target_path` と `target_secrets_path` が並び、パスの組み立てが二重になっていた。
- upload: install 時に通常ツリーと secret ツリーを別々に upload し、ノード上の隠しディレクトリ（`.kubernetes`, `.bootstrap`, `.kubelet` など）から `cp -r` で合流させていた。
- 平文の secret が assets ディレクトリにあるため、assets を git 管理できなかった。

## 決定事項

| 項目 | 決定 | 理由 |
|---|---|---|
| レイアウト | `assets/secrets/` を廃止し、secret も `assets/<group>/...` に置く | secret を特別扱いせず、render と upload の経路を一本にする |
| 暗号化の判定 | ファイル名は変えない。中身の YAML / JSON にトップレベルの `sops` キーがあれば暗号化済みとみなす | ローカルとノードでパスが一致し、テンプレートやスクリプト内のパス参照を変えずに済む |
| 暗号化の形式 | secret はすべて sops の binary 形式で暗号化する（YAML の secret も含む） | 下記「binary 形式を選んだ理由」を参照 |
| 暗号化の対象 | porkadot のコードが secret の出力に印を付け、その出力だけを暗号化する。鍵はユーザーの `.sops.yaml` の `creation_rules` で sops が解決する | secret かどうかを知っているのは porkadot であり、暗号化漏れを防げる |
| 有効化 | `local.sops.enabled`（既定 `false`）。`local.sops.config` で `.sops.yaml` を明示できる | 互換性のため。sops の無い環境やテストでも動く |
| upload | 一時ディレクトリに展開せず、ファイルごとに読み、暗号化済みなら復号した内容をメモリから upload する | 平文をローカルディスクに書かない |
| ローカル読み込み | 証明書や鍵の再利用、`set-config` などの読み込みも同じ読み込み口を通し、メモリ上で復号する | 暗号化したままで再 render や証明書ローテーションができる |
| 再 render | 書き込み前に既存ファイルを復号して比較し、平文が同じなら書き込まない | sops の暗号文は毎回変わる。無意味な差分を防ぎ、`diff -ru` での回帰確認を維持する |
| 移行 | `porkadot migrate-secrets` で旧レイアウトを移動する（sops 有効時は同時に暗号化）。旧レイアウトが残っている間、assets を使うコマンドはエラーで止まる | CA を失う事故を防ぐ。暗黙の自動移行はしない |

### binary 形式を選んだ理由

sops の YAML 形式は、暗号化してから復号すると元のバイト列に戻らない。dev クラスタ設定で生成した `kube-apiserver.secrets.yaml` と `kubeconfig.yaml` で確認したところ、先頭の `---` が消え、リストのインデントが変わった。

YAML 形式を使うと次の問題が出る。

- upload 時の復号結果が従来の平文と一致しない（意味は同じでもバイトが違う）。
- 再 render 時の「平文が同じなら書かない」がバイト比較では常に不一致になり、毎回再暗号化されて差分が出続ける。

binary 形式なら、復号結果は元のバイト列と完全に一致する。出力は `data` と `sops` をキーに持つ JSON になり、トップレベルの `sops` キーで判定する方針とも矛盾しない。

代わりに `sops edit` で YAML として構造編集することはできない。secret は porkadot が生成するものであり、手で編集する運用は想定しないため、この制約は受け入れる（ユーザー判断）。

## secret として扱う出力

旧レイアウトで `assets/secrets/` に置いていたファイルを、そのまま secret として扱う。移動先は次のとおり。

| 出力 | 統合後のパス |
|---|---|
| PKI（CA・各証明書と鍵・SA 鍵） | `certs/{kubernetes,etcd}/...` |
| bootstrap node へ渡す証明書一式 | `bootstrap/bootstrap/secrets/...` |
| bootstrap node の kubelet ブートストラップ鍵 | `bootstrap/kubelet/bootstrap.key` |
| 各ノードの kubelet ブートストラップ鍵 | `kubelet/{node}/bootstrap.key` |
| etcd メンバーの証明書・鍵・CA | `kubelet/{node}/addons/etcd/{etcd.crt,etcd.key,ca.crt}` |
| admin kubeconfig | `kubernetes/kubeconfig.yaml` |
| secret マニフェスト | `kubernetes/manifests/{kube-apiserver,kube-controller-manager}.secrets.yaml`、addon の secret マニフェスト |
| secret マニフェストの適用スクリプト | `kubernetes/install.secrets.sh` |

公開情報の証明書でも、旧レイアウトで secret ツリーにあったもの（`certs/` 配下の `.crt` など）は secret として扱う。`migrate-secrets` が旧ツリーをまとめて暗号化することと揃えるためである。逆に、従来から通常ツリーにあった `kubelet/{node}/bootstrap.crt` と `kubelet-default/ca.crt` は平文のままにする。

統合後に通常ファイルと secret のパスが衝突しないことは、dev クラスタ設定で生成した全ファイル（secret 57 件）を突き合わせて確認した。衝突は無い。

## 実装方針

### 読み書きの集約（`AssetStore`）

assets ディレクトリへの読み書きは、すべて `Porkadot::AssetStore`（`Config#asset_store`）を通す。

- 書き込み: secret の印が付いた出力はモード 0600 で書く。sops が有効なら暗号化してから書く。既存ファイルを復号した内容が新しい内容と同じなら書き込まない。ただし sops 有効時に既存の secret が平文なら、内容が同じでも暗号化して書き直す。
- 読み込み: 中身が暗号化済みなら、`local.sops.enabled` の値にかかわらず復号した内容を返す。
- ERB の出力は `render_erb` に secret の印を渡す形にし、`render_secrets_erb` を廃止した。証明書・鍵の生成と再利用、bootstrap 用の証明書コピー、CRD のコピーも同じ口を通る。

### sops ラッパー（`Porkadot::Sops`）

sops の呼び出しは小さなラッパーに閉じ込める。テストでは偽物に差し替えられる。

- 入出力は標準入出力で受け渡し、平文を一時ファイルに書かない。
- 暗号化は binary 入力・JSON 出力で行う。復号は JSON なら binary 出力、それ以外（利用者が YAML 形式で暗号化したもの）は YAML 出力にする。
- `--filename-override` に asset の絶対パスを渡し、`.sops.yaml` の `path_regex` で鍵を選ばせる。sops は `.sops.yaml` のあるディレクトリからの相対パスで照合する。
- cwd は `porkadot.yaml` のあるディレクトリにする。`local.sops.config` があれば `--config` で渡す（相対パスは `porkadot.yaml` 基準）。
- sops が失敗したら `Porkadot::Error` にして止める。

### upload（`Install::Uploader`）

ツリーをファイルごとに辿って upload する。

- ローカルの相対パスをそのままリモートの相対パスにする。必要なディレクトリは一度の `mkdir -p` で作る。
- 内容は `AssetStore` で読み（暗号化済みなら復号され）、メモリから upload する。
- パーミッションはローカルファイルのモードをそのまま渡す。secret は 0600、通常ファイルは従来どおり umask に従う。ノード上では install スクリプトが root で `cp` するため、配置先のファイルは root 所有になる。
- kubelet では `kubelet-default` のツリーにノード固有のツリーを重ねて、同じ一時ディレクトリへ upload する。

### ノード側の変更

- 隠しディレクトリ（`.kubernetes`, `.bootstrap`, `.kubelet`, `.default`, `.default.kubelet`, `.rotate-certs-etcd`）は使わなくなった。古い porkadot が残した平文が残らないよう、install 時に削除する。
- `install kubernetes` は `KUBECONFIG` を通常の一時ディレクトリの `kubeconfig.yaml` に向け、同じ場所の `install.secrets.sh` を実行する。
- `install.secrets.sh` は `manifests/` を `-R` で丸ごと適用していた。統合後の `manifests/` には通常マニフェストや `kustomization.yaml` も入るため、secret マニフェストをファイル名で指定して適用する形に変えた。secret マニフェストは従来どおり kustomization の外で適用し、prune の対象にしない。

### 移行（`porkadot migrate-secrets`）

- `assets/secrets/` 配下の全ファイルを `assets/` 直下の同じ相対パスへ secret として書き込み、最後に `assets/secrets/` を削除する。sops 有効時は書き込み時に暗号化される。
- 移動先に内容の異なるファイルが一つでもあれば、何も変更せずにエラーで止まる。同じ内容なら衝突とはみなさない。
- 移行後に `render kubelet` / `etcd` / `bootstrap` / `kubernetes` を実行して、新しいレイアウト用のスクリプト（`install.secrets.sh`）を生成し直す。`render certs` は不要（CA を作り直さないこと）。

### 旧レイアウトの検知

`assets/secrets/` が存在する間は、assets を読み書きするコマンド（`render`、`install`、`rotate-certs`、`set-config`、`setup-node`、`setup-containerd`）はエラーで止まり、`migrate-secrets` を案内する。

- `render` は決定事項として止める。
- `install` などは、旧レイアウトのまま実行すると secret の無いツリーを upload してしまう。`set-config` は証明書が見つからないと新しい CA を生成してしまう。このため同様に止める。
- `etcd`（backup / restore / start / stop）は assets を使わず、障害対応で使うため止めない。

## 変更対象

- `lib/porkadot/asset_store.rb`、`lib/porkadot/sops.rb`、`lib/porkadot/install/uploader.rb`、`lib/porkadot/cmd/migrate_secrets.rb`（新規）
- `lib/porkadot/config.rb`、`lib/porkadot/config_validator.rb`、`lib/porkadot/default.yaml`、`lib/porkadot/utils.rb`
- `lib/porkadot/configs/`（secret 用パスの廃止）
- `lib/porkadot/assets.rb`、`lib/porkadot/assets/`（secret の印、`AssetStore` 経由の読み書き）
- `lib/porkadot/assets/kubernetes/install.secrets.sh.erb`
- `lib/porkadot/install/`（`Uploader` による upload、ノード側パス）
- `lib/porkadot/cmd/cli.rb`、`lib/porkadot/cmd/etcd.rb`

## テスト

- 本物の sops と age を使うテストは、テスト内で一時 age 鍵と `.sops.yaml` を生成する。`sops` か `age-keygen` が無い環境でだけ skip する。
  - 暗号化・復号の往復でバイト列が一致する。出力が binary 形式である。
  - render で secret だけが暗号化される。
  - 再 render で、内容の変わらない secret ファイルがバイト単位で変化しない。
  - 平文で生成した証明書を旧レイアウトに置き、sops 有効で `migrate-secrets` → render → upload した内容が、平文の render と一致する。
- `AssetStore` は偽の sops で、暗号化の有無、同一内容のスキップ、内容変更時の再暗号化、平文の secret の暗号化を確認する。
- レイアウト: secret の出力先、モード 0600、`assets/secrets/` が作られないこと、旧レイアウト検知でのエラー。
- `migrate-secrets`: 移動、衝突時に何も変更しないこと、同一内容の扱い。
- `Uploader`: 相対パスの維持、モード、複数ツリーの重ね合わせ。

## 回帰確認

dev クラスタ設定で、変更前（master）と変更後の render 結果を比較する。

- 両者を同じ assets スナップショット（master で生成したもの）から始める。変更後は `migrate-secrets` を実行してから `render kubelet / etcd / bootstrap / kubernetes` を実行する。
- `secrets/` 接頭辞を外して突き合わせ、差分が次だけであることを確認した。
  - `kubernetes/install.secrets.sh`（意図した変更）
  - render のたびに再署名される `bootstrap.crt` と etcd の `etcd.crt`（master 同士の比較でも同様に変わる）
- sops 有効時も同じ手順で確認した。secret 57 件がすべて暗号化され、再 render で変化したのは再署名される証明書だけだった。upload 時の復号結果は平文版と一致した。

## 非対象

- 実クラスタへのデプロイ確認。
- sops の鍵管理（age 鍵の配布、`.sops.yaml` の内容）。利用者の設定に任せる。
- 手で編集した YAML 形式の暗号化ファイルの書き戻し。porkadot は読み込み（復号）だけに対応し、書き込むときは binary 形式で暗号化し直す。
