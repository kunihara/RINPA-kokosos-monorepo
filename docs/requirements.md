# KokoSOS 要件定義（CodeX CLI 用）

## サービス概要
- サービス名：KokoSOS
- ターゲット：個人利用（家族・友人・恋人向け）
- 目的：危険を感じたときに最小操作（アプリ起動）で信頼できる相手に緊急通知。
- 特徴：
  - 緊急モード：起動→3秒カウントダウン→通知→60分間位置共有（自動停止/延長可）
  - 帰るモード：出発と到着のみ通知（ジオフェンス）。途中で緊急に切替可能。
  - 通知方法：プッシュ通知（将来）、メール（MVPでは必須）。SMSはスコープ外。
  - 受信者体験：メールリンクからWebページを開き、現在地・最終更新・残り時間を確認。CTA（電話/プリセット返信/110に誘導）。リンクは24h有効、即時失効可。

---

## アーキテクチャ概要
- iOSアプリ：UIKit/Swift。CoreLocationで位置取得。3秒カウントダウン→API呼び出し。
- API：Cloudflare Workers（TypeScript）。JWTトークン認証。SSEで受信者にライブ配信。
- DB：Supabase（Postgres + RLS）。alerts/locations等の短期保持（24〜48hで自動削除）。
- 受信Webページ：Next.js 14 (App Router)。静的SPAシェル＋APIからデータ取得。EventSourceでSSE購読。
- 通知：AWS SESでメール送信（招待・SOS通知）。APNsは将来対応。
- 地図：Mapbox。
- ホスティング：WebはCloudflare Pages、APIはWorkers。

---

## データモデル（最小）
- users(id, apple_sub, apns_token, email, created_at)
- contacts(id, user_id, name, email, role, capabilities)
- alerts(id, user_id, type[emergency|going_home], status[active|ended|timeout], started_at, ended_at, max_duration_sec, revoked_at)
- locations(id, alert_id, lat, lng, accuracy_m, battery_pct, captured_at)
- deliveries(id, alert_id, contact_id, channel[push|email], status, created_at)
- revocations(alert_id, revoked_at)
- reactions(id, alert_id, contact_id, preset, created_at)  ← 受信者のプリセット返信を保存

保持期間は alerts/locations/deliveries を 24〜48h に制限。

---

## APIエンドポイント

### 送信者用 (iOSアプリ)
- POST `/alert/start` … 共有開始（初期位置・バッテリー送信／shareToken生成／メール送信）
- POST `/alert/:id/update` … 定期位置更新（1〜5分間隔）
- POST `/alert/:id/stop` … 停止／到着通知
- POST `/alert/:id/extend` … 共有時間を延長（max_duration_sec を +N秒／サーバ側で5分〜6時間にクランプ）
- POST `/alert/:id/revoke` … 即時失効

### 受信者用 (Web公開API・JWT必須)
- GET `/public/alert/:token` … 初期データ（種別type・状態・最新位置・残り時間・権限）
- GET `/public/alert/:token/stream` … SSEによるライブ更新
- POST `/public/alert/:token/react` … プリセット返信（受信者→送信者へAPNs通知想定）

SSEイベント（例）
- `{ type: 'hello' | 'keepalive' }`
- `{ type: 'location', latest: { lat, lng, accuracy_m, battery_pct, captured_at } }`（emergency のみ）
- `{ type: 'status', status: 'active' | 'ended' | 'timeout' }`
- `{ type: 'extended', remaining_sec, max_duration_sec, added_sec }`
- `{ type: 'reaction', preset, ts }`

---

## セキュリティ
- トークン：JWT署名付き。含む情報は alert_id, contact_id, scope, exp (≤24h)
- 失効：revocationsテーブルを参照して即時無効化可能。
- HTTPヘッダ：
  - HSTS
  - Referrer-Policy: no-referrer
  - X-Frame-Options: DENY
  - CSP (nonceベース、第三者スクリプト最小)
- ログ：トークンは必ずマスク化して保存。
- データ最小化：名前や電話番号は受信者権限に応じて制御。
- 権限（受信者）：JWTに`contact_id`がある個別招待リンクのみ返信可（`can_reply=true`）。汎用共有トークンは返信不可。

---

## フロントエンド (Web)
- Route: `/s/[token]`
- 初期表示：ローディングUI
- 初期Fetch: `/public/alert/:token` → 状態, 位置, 残り時間
- SSE購読: `/public/alert/:token/stream` → ライブ更新（延長・返信も即時反映）
- UI要素：
  - ステータス（共有中/終了/期限切れ）
  - 地図（現在地ピン＋精度円、簡易履歴）※ going_home では非表示
  - 最終更新時刻・残り時間（1秒カウントダウン）・バッテリー
  - 延長トースト（例: 「+X分延長されました」）
  - 返信トースト（例: 「返信: OK」）
  - CTAボタン：電話・プリセット返信（複数プリセット）・110へ電話（権限に応じて制御）

---

## インフラと運用
- 開発/デプロイ：
  - Workers → wrangler dev/deploy
  - Web → Cloudflare Pages 自動ビルド
  - DB → supabase db push
- Secrets管理：`.env` を用意し `.env.example` を共有。GitHub Secrets に登録。
- 監視：UptimeRobotでヘルスチェック。Cloudflare Analyticsでアクセス確認。
- 運用コスト：
  - 小規模（数千MAU）：数ドル〜数十ドル/月
  - メールSESとMapbox以外は無料枠で十分

---

## Push通知（将来計画）

方針（iOS/Android/Webを見据えた最適解）
- メッセージ基盤: Firebase Cloud Messaging (FCM) を採用
  - iOSは FCM→APNs 経由、Androidは FCM 直配信
  - 無料枠が厚く、クロスプラットフォームで一元化しやすい
- 送信サービス: AWS Lambda（Node.js + Firebase Admin SDK）
  - 再試行や無効トークン回収を実装しやすい
  - 秘密情報は AWS Secrets Manager で管理
- 連携: Cloudflare Workers →（Cloudflare Queues）→ Lambda
  - Workers は通知イベント発火役に専念、バーストはQueuesで吸収

WorkersからAPNs直送を避ける理由
- APNsはHTTP/2前提で、Workersの外向きfetchは任意オリジンへのHTTP/2を保証しないため運用上の不安定リスクがある
- FCM採用によりHTTP/1.1ベースの送信やAdmin SDK利用で実装が簡素化

データモデル（将来追加）
- devices(id, user_id, platform[ios|android|web], fcm_token, valid, last_seen_at, created_at)

API（将来追加）
- POST /devices/register … fcm_token登録（user紐付け・プラットフォーム付与）
- POST /devices/unregister … fcm_token無効化
- 既存イベント発火はWorkersが担当（reaction/opened/extended）

イベントスキーマ（Queues→Lambda）
- 共通: { id, type: 'reaction'|'opened'|'extended', user_id, tokens: string[], data: {...}, ts }
- 例: reaction → data = { preset }
- 例: opened → data = { ua, ip (オプション) }
- 例: extended → data = { added_sec, remaining_sec }

Lambda実装メモ
- Firebase Admin SDKで sendMulticast / sendEachForMulticast を使用
- 応答で無効トークン(410/invalid)を回収し devices.valid=false
- 429/5xxは指数バックオフで再試行、DLQ(SQS)へ退避

セキュリティ
- Firebaseサービスアカウント鍵はSecrets Manager（KMS）で暗号化・最小権限・定期ローテーション
- Apple開発者プログラム登録（$99/年）とAPNs設定（FCMコンソール）

概算コスト（小規模）
- FCM: 無料
- Lambda/API Gateway/Queues: 無料枠〜数ドル/月
- Apple Developer Program: $99/年

導入ロードマップ
1) devicesテーブルと /devices/register を先に実装（クライアントのトークン収集）
2) Workers→Queues→Lambdaの経路を用意（最初はWebhookでも可）
3) reaction/opened/extended の通知種別を段階導入（まずは reaction）
4) 監視/再試行/無効トークン回収の運用整備

## 追加要件
- MVPでは録音・録画は非搭載（将来の拡張候補）
- 最大共有時間は60分（延長可能）。帰るモードは設定から最大共有時間を変更可能（既定120分）。
- 「帰るモード」は出発・到着のみ通知（経路共有なし）／送信者は到着時に手動停止。
- iOSはローカル通知でリマインダー（既定30分後／設定で変更可／バックグラウンドでも通知）。
- 受信ページリンクは24hで失効、即時失効可
- メール送信時に受信者ごとに固有トークンURLを生成（誤共有リスクを抑止）
