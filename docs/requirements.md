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

保持期間は alerts/locations/deliveries を 24〜48h に制限。

---

## APIエンドポイント

### 送信者用 (iOSアプリ)
- POST `/alert/start` … 共有開始（初期位置・バッテリー送信／shareToken生成／メール送信）
- POST `/alert/:id/update` … 定期位置更新（1〜5分間隔）
- POST `/alert/:id/stop` … 停止／到着通知
- POST `/alert/:id/revoke` … 即時失効

### 受信者用 (Web公開API・JWT必須)
- GET `/public/alert/:token` … 初期データ（状態・最新位置・残り時間・権限）
- GET `/public/alert/:token/stream` … SSEによるライブ更新
- POST `/public/alert/:token/react` … プリセット返信（受信者→送信者へAPNs通知想定）

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

---

## フロントエンド (Web)
- Route: `/s/[token]`
- 初期表示：ローディングUI
- 初期Fetch: `/public/alert/:token` → 状態, 位置, 残り時間
- SSE購読: `/public/alert/:token/stream` → ライブ更新
- UI要素：
  - ステータス（共有中/終了/期限切れ）
  - 地図（現在地ピン＋精度円、簡易履歴）
  - 最終更新時刻・残り時間・バッテリー
  - CTAボタン：電話・プリセット返信・110へ電話（権限scopeで制御）

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

## 追加要件
- MVPでは録音・録画は非搭載（将来の拡張候補）
- 最大共有時間は60分（延長可能）
- 「帰るモード」は出発・到着のみ通知（経路共有なし）
- 受信ページリンクは24hで失効、即時失効可
- メール送信時に受信者ごとに固有トークンURLを生成（誤共有リスクを抑止）
