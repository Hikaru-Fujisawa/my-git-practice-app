# Shopee Indonesia 売れ筋ランキング DB

Shopee Affiliate の公式ランキングを毎日 09:00 WIB に記録し、7日・30日の推移を追跡するためのデータベースです。

- 7D: **Produk Trending**（販売の伸びが大きい順。販売増加ランキング）
- 30D: **Produk Terlaris**（販売数量の多い順。販売数量ランキング）

この2つは別々のシートに保存し、混ぜて扱いません。

## 構成

| パス | 内容 |
|---|---|
| `pipeline.py` | 取り込み、検証、重複除外、差分計算、xlsx 生成 |
| `inbox/TEMPLATE_7D.csv` / `TEMPLATE_30D.csv` | 取り込み用 CSV のテンプレート |
| `inbox/processed/` | 取り込みが済んだ CSV の移動先 |
| `data/Ranking_7D.csv` / `Ranking_30D.csv` | ランキング履歴（追記のみ。これが正本） |
| `data/Latest_Top30.csv` | 最新の 7D と 30D を横に並べた表 |
| `data/Trend_Analysis.csv` | 前回順位、変動、新規、連続ランクイン日数、価格変動、注目理由 |
| `data/Run_Log.csv` | 毎回の実行記録（失敗した回も残す） |
| `data/Reference_Public.csv` | 公開売れ筋ページの参考データ（公式ランキングとは別に管理） |
| `data/Shopee_ID_Ranking_DB.xlsx` | 上の5シートをまとめたもの（Google Sheets 取り込み用） |

Google Sheets: `Shopee_ID_Ranking_DB`（Drive 上のマイドライブ）

## 毎日の手順

1. 正規のログイン済みブラウザで https://affiliate.shopee.co.id/offer/product_offer を開きます。
2. Produk Trending を表示し、全カテゴリー・全価格帯・チャネル「Semua」に設定して、1〜30位を `TEMPLATE_7D.csv` の形式で `inbox/` に保存します。
3. Produk Terlaris も同じ条件で `TEMPLATE_30D.csv` の形式で保存します。
4. `python3 pipeline.py ingest` を実行します。
5. 取得できなかった日は `python3 pipeline.py ingest --fail-reason "理由"` を実行して Run_Log に残します。

### inbox CSV のルール

- 先頭の `#` 行がメタデータです。`source`、`period`、`captured_at_wib`、`source_url`、`conditions`、`shortfall_reason` を書きます。
- `source` に使える値:
  - `affiliate_trending`（7D）
  - `affiliate_terlaris`（30D）
  - `mcn`（`period` の指定が必要）
  - `public_bestseller`（参考データ。Reference_Public に入ります）
- `product_url` が `-i.{shopid}.{itemid}` または `/product/{shopid}/{itemid}` の形なら、店舗ID と商品ID を自動で取り出します。
- `sales_qty_scope` には、表示されている販売数量がどの期間の数字かを書きます（`7D` / `30D` / `total` / 空欄）。この値がランキングの対象期間と一致し、価格が単一の値のときだけ推定売上高を計算します。それ以外は空欄のままにします。
- 30件に届かない場合は、取れた件数だけを入れ、`shortfall_reason` に理由を書きます。架空の行で埋めないでください。

## データ規則

- 同じ取得日・同じ対象期間・同じ商品は二重に登録しません。2回目の取り込みは `DUPLICATE` として記録します。
- 履歴は追記のみで、過去の行は消しません。前回順位、順位変動、新規ランクインは、直前の取得日と比べて毎回計算し直します。
- 順位変動はプラスなら上昇です（前回順位 − 今回順位）。
- 初回の取得日は比較対象がないため、新規ランクイン欄は空欄になります。
- Shopee の検索結果の並び順や「terjual」の多さを、公式順位として扱いません。

## 取得経路と認証（2026-10-22 初回確認）

| 経路 | 状態 |
|---|---|
| Affiliate ポータル（affiliate.shopee.co.id） | 到達可能。`/api/v3/user/profile` が `30001 no login` を返すため、ログインが必要 |
| Affiliate Open API（open-api.affiliate.shopee.co.id/graphql） | 到達可能。AppID/Secret による署名がないと `10020 Invalid Authorization Header` |
| MCN ランキング | 権限が未確認 |

Open API の `productOfferV2` の list/sort 種別が、ポータルの Produk Trending / Terlaris と同じものかは公開資料で確認できていません。認証情報が手に入ったら、ポータルの表示と照合してから公式ランキングとして扱ってください。照合が済むまでは別の source として記録します。
