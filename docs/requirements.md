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
- 送信者認証：Supabase Auth（Email/Password, Apple, Google, Facebook）。WorkersはSupabaseのJWT(RS256)をJWKSで検証しuser_idを抽出
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

## iOS クライアント接続仕様（追記）

- 呼び出すAPI（Cloudflare Workers）
  - 送信者用: `POST /alert/start` / `POST /alert/:id/update` / `POST /alert/:id/stop` / `POST /alert/:id/extend` / `POST /alert/:id/revoke`
  - 公開用（参考）: `GET /public/alert/:token` / `GET /public/alert/:token/stream` / `POST /public/alert/:token/react`
  - 認証: `Authorization: Bearer <Supabase access_token>`（`REQUIRE_AUTH_SENDER=true` 時は必須）

- 接続先の決定順序（iOSアプリ内の実装）
  1) アプリ内「設定 > APIベースURL」の上書き値（http/https かつ host 必須のときのみ採用）
  2) Info.plist の `APIBaseURL`（有効なURLのとき）
  3) Info.plist の `APIBaseHost` + `APIBaseScheme`（ホスト/ポート指定からURLを組み立て）
  4) フォールバック: `http://localhost:8787`（Dev想定）

- xcconfig/Info のキー（Secrets-*.xcconfig で上書き可）
  - Info.plist: `APIBaseURL`, `APIBaseHost`, `APIBaseScheme`
  - xcconfig: `API_BASE_URL`, `API_BASE_HOST`, `API_BASE_SCHEME`
  - 備考: `API_BASE_URL` に `https://...` を直書きすると `//` 以降がコメント扱いになるケースがあるため、ステージ/本番では `API_BASE_HOST=kokosos-api-<env>.<your>.workers.dev` と `API_BASE_SCHEME=https` を推奨。

- 実機での注意
  - 実機は `localhost` に到達できないため、公開ドメイン（例: workers.dev のサブドメインやカスタムドメイン）またはLAN IPを指定する。
  - DevはATS緩和（http可）。Stage/Prodはhttps必須。

- エラーハンドリング（アプリ表示）
  - ホスト解決失敗（cannotFindHost）: 「設定 > APIベースURL」で到達可能なURLを促すメッセージを表示。
  - サーバー非2xx（-1011 等）: `サーバーエラー(ステータス)` とレスポンスJSONの `error/detail` を整形して表示（401/400/500 の切り分けが容易）。

- トラブルシュート
  - ヘルスチェック: `GET https://<APIホスト>/_health` で `REQUIRE_AUTH_SENDER` / `SUPABASE_URL_preview` などを確認。
  - 401 invalid_token: Workers の `SUPABASE_URL` が iOSのSupabaseプロジェクトと不一致、またはトークン未送付。
  - 500 server_misconfig: Workers の `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` 未設定。
  - 400 invalid_location: `lat/lng` 未送信。

- 実装メモ（URL組み立て）
  - エンドポイントはパスセグメントで結合する（例: `("alert", "start")`）。先頭 `/` を含む文字列を `appendingPathComponent("/alert/start")` に渡すと `%2Falert%2Fstart` となり 404 になるため注意。

---

## 認証（サインアップ/サインイン）仕様（更新）

ゴール
- 最短でログイン/登録できる明快な導線。
- 失敗時の理由が明確で、自己解決（再送・再入力）が可能。
- メール検証・パスワード再設定・OAuthに自然に接続。

主要フロー
- サインイン: Email + Password、または OAuth(Apple/Google/Facebook)。
- サインアップ: Email + Password → 確認メール → 検証後にアプリ復帰。
- パスワード再設定: Email入力 → リセットメール → 新パスワード設定。
- リンク復帰: OAuth/検証/リセットは Deep Link でアプリ復帰。

画面構成（モバイル）
- 初期表示: サインイン（未ログイン時）
  - フィールド: Email, Password（表示/非表示切替）。
  - ボタン: 「ログイン」「パスワードをお忘れですか？」
  - OAuth: 「Appleで続ける」「Googleで続ける」「Facebookで続ける」。
  - 下部リンク: 「新規登録の方はこちら」→ サインアップへ遷移。
- サインアップ（別画面）
  - フィールド: Email, Password（強度の目安/ポリシー表示）。
  - ボタン: 「登録する」。
  - OAuth: 「Apple/Google/Facebookで続ける」（他の方法で続行）。
  - 結果画面: 「確認メールを送信しました」（メール内リンクの案内）。
- パスワード再設定
  - フィールド: Email。
  - 結果画面: 「リセットメールを送信しました」（レート制限あり）。
- 検証完了（Web→アプリ）
  - 表示: 「登録/受信許可を確認しました」→「アプリに戻る」。
- ログイン後初回
  - サインアップ直後のみ、受信者オンボーディングを自動表示（1回）。
  - サインイン後は表示しない（設定から編集可能）。

入力・バリデーション
- Email: トリム/小文字化/簡易正規表現、未入力/形式エラーの明示。
- Password: 8文字以上（推奨: 英数記号混在）。
- エラー表示: フィールド下に具体的メッセージ＋上部アラート。
- ローディング: ボタン内スピナー、二重送信防止。

メール検証（Sign-up Verify）
- サインアップ直後に確認メールを送信。
- 検証リンク: `WEB_PUBLIC_BASE/verify/:token` → 検証成功表示 → Deep Linkでアプリ復帰。
- 確認メールの再送: 現行UIではサインイン画面からは提供しない（混乱防止）。必要に応じてヘルプ等から提供を検討。

パスワード再設定
- 入力: Email のみ。
- リンク到達後: 新パスワード設定画面（Web or アプリ）→ 完了後にアプリ復帰。

OAuth（Apple/Google/Facebook）
- 1タップでサインイン/サインアップ（同一メールは同一アカウントに統合）。
- ASWebAuthenticationSession を使用。キャンセル/戻るの明示。
- 取得スコープは最小（email/profile）。

セッション管理
- 保存: access_token（短命）、refresh_token（安全な保管）。
- 自動ログイン: 起動時にトークン検証/更新、失敗時はサインインへ。
- サインアウト: トークン破棄、個人情報キャッシュ削除。

エッジケース/メッセージ
- 未検証メールでサインイン: 「メールの確認が必要です」→ 再送導線。
- 既存メールでサインアップ: 「すでに登録済みです」→ サインインへ。
- OAuth衝突（別プロバイダ同メール）: 「別の方法で登録済み」→ 案内。
- ネットワーク不通/レート制限: 再試行メッセージ。

法務/設定
- 規約/プライバシーリンクをフッター等に常設。
- 同意が必要な場合は初回のみ表示。

アクセシビリティ/国際化
- VoiceOver/フォーカス順、十分なコントラスト。
- 既定日本語、将来英語対応。

実装ノート（iOS）
- 画面: AuthContainer（タブ: ログイン/新規登録）/ SignIn / SignUp / ForgotPassword / VerifyPending。
- Deep Link: 既存 `OAuthRedirectScheme` を流用（verify/resetも同スキームで処理）。
- Supabase連携（参考）
  - パスワード: `POST /auth/v1/token?grant_type=password`
  - サインアップ: `POST /auth/v1/signup`（`email_redirect_to` 指定）
  - パスリセット: `POST /auth/v1/recover`
  - OAuth: `GET /auth/v1/authorize?provider=...`

導入順（提案）
1) サインイン/サインアップ/パスリセットの骨子 + Supabase連携（画面分離、サインイン初期表示）。
2) Deep Link整備、OAuth(Apple/Google/Facebook)。
3) エラー文言/アクセシビリティ調整、計測。
4) サインアップ直後の受信者オンボーディング接続（サインイン後は設定から）。

## インフラと運用

---

## 受信者選定・検証（追加仕様）

目的
- 無差別送信を避け、送信前に「誰に送るか」を明示選択する。
- 連絡先に存在しない相手でもメール入力で迅速に登録できる。
- 検証済み（verify済）の受信者のみを既定で送信対象にする。

送信前フロー（MVP）
- 初回オンボーディング
  - ステップ: 説明 → 権限（位置情報）→ 受信者の設定 → 状態確認 → 完了
  - 受信者の設定: メールアドレスを入力（複数可、カンマ/改行対応）。追加したメールは pending として一覧に表示し、「確認メールを送信」で検証メールを一括送信。
  - 状態確認: pending/verified を表示。未検証は「再送」が可能。
- メイン画面（送信前）
  - 「受信者を選択（検証済み）」のチップを常時表示。タップでピッカーを開く。
  - 緊急/帰るボタンは「既定の受信者セット」があれば1タップ開始。なければピッカーへ誘導。

受信者ピッカー（UI）
- 上部: 検索＋「メールを追加」入力欄（未登録メールはその場で候補化）。
- リスト: 名前/メール/ステータス（verified/pending）/役割（家族・友人等）。
- セクション/タブ: すべて / お気に入り / 検証済み / 最近。
- 選択ルール: 既定は verified のみ選択可（pending は灰色・選択不可）。
- 下部: 選択件数＋決定（0件は無効）。
- 既定セット: モード別（緊急/帰る）に既定受信者を保存/上書き。

送信ルール
- 緊急モード: start 時に「選択受信者（verifiedのみ）」へメール送信。
- 帰るモード: start（任意/設定）＋ stop（到着）で同じ受信者にメール送信。
- サーバー側で受信者自動補完（contacts全件）などの無差別送信は行わない。

検証（verify）フロー
- 検証メール: 「KokoSOS からの受信許可の確認」リンクを送付。`WEB_PUBLIC_BASE/verify/:token`。
- Web側で token を検証し `contacts.verified_at` をセット。完了画面を表示。
- アプリのピッカーでは verified のみ選択可能（将来オプションで未検証許可も可）。

データモデル（拡張）
- contacts
  - 追加: `verified_at timestamptz`（null=未検証）。
  - 既存: `role text`, `capabilities jsonb`（`notify_emergency`, `notify_going_home`, `email_allowed` など。未設定は true 扱い）。
- contact_verifications（新規）
  - `id, contact_id, token_hash, created_at, used_at, expires_at`（token本体は保存しない）。
- alert_recipients（新規）
  - `alert_id, contact_id, email, purpose('start'|'arrival'), created_at`（到着通知に同一受信者を再利用）。

API（最小追加案）
- `GET /contacts?status=verified|pending|all` … ピッカー表示用。
- `POST /contacts/bulk_upsert` … `{ contacts: [{ email, name?, role? }] }` を pending で作成/更新（オプションで `send_verify=true`）。
- `POST /contacts/:id/send_verify` … 検証メール再送。
- `GET /public/verify/:token` … 検証確定（`verified_at` セット）。
- `POST /alert/start` … `recipients: string[]` を必須に（未検証を含む場合は 400 + `invalid_recipients`）。
- `POST /alert/:id/stop` … `alert_recipients` を参照し、going_home の到着通知を送信。

優先表示/効率化
- 並び順: お気に入り > 役割（家族）> 最近使用 > その他。
- クイックフィルタ: 役割「家族」。
- 入力補助: 重複排除・簡易バリデーション・ペースト複数追加。

段階導入
1) contacts.verified_at と検証エンドポイントを実装。
2) iOS オンボーディング（受信者入力→検証送信→状態表示）。
3) 受信者ピッカー＋既定セット。`/alert/start` は recipients 必須・未検証は不許可。
4) `alert_recipients` と到着通知（going_home）を実装。
- 開発/デプロイ：
  - Workers → wrangler dev/deploy
  - Web → Cloudflare Pages 自動ビルド
  - DB → supabase db push
- Secrets管理：`.env` を用意し `.env.example` を共有。GitHub Secrets に登録。
- Supabase Auth: Providers（Apple/Google/Facebook/Email）を有効化。Redirect URL設定。Workers側は `SUPABASE_URL`/`SUPABASE_JWKS_URL` を設定。
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
