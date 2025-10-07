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

## iOS 認証（仕様更新: supabase-swiftへ移行）

- 概要
  - iOSの認証は `supabase-swift` を採用し、セッション保持・リフレッシュ・イベントをSDKに委譲。
  - 旧自前Auth（UserDefaultsでのtoken保存）は廃止。Authorizationは常にSDKセッションの`accessToken`を使用。

- フロー
  - サインイン: `auth.signInWithPassword(email, password)`
  - サインアップ: `auth.signUp(options: .init(emailRedirectTo: <redirect>))`
  - パスワード再設定: `auth.resetPasswordForEmail(email, redirectTo: <redirect>)`
  - OAuth(Apple/Google/Facebook): `auth.signInWithOAuth(provider, options: .init(redirectTo: "<scheme>://oauth-callback", scopes: "email profile offline_access"))`
  - `OAuthRedirectScheme` は Info.plist に設定（例: `kokosos`）。

- セッション・リフレッシュ
  - アプリ起動/復帰時に `refreshSession()` を静かに実行。
  - API 呼出時に401なら `refreshSession()` → 再試行（SDK側で直列化/Keychain保存）。
  - サインアウト: `auth.signOut()` → 画面をサインインへ遷移。

- 開発用診断
  - Workers: `GET /_diag/whoami` で Authorization の検証結果（JWKS/フォールバック）を返却。401切り分けに使用。

---

## アカウント削除（追加）

- 目的：ユーザーがアプリ内の「アカウント削除」操作で、本人の認証情報と関連データ（contacts/alerts/locations/deliveries…）を安全に削除できるようにする。

- クライアント（iOS）
  - 設定 > アカウント削除（確認ダイアログ）→ API `DELETE /account` を呼び出し。
  - 成功後はトークンを破棄しサインイン画面へ遷移。

- API（Workers）
  - `DELETE /account`（Authorization 必須）
    - 認証トークンから `user_id` を取得。
    - Supabase REST（Service Role）でアプリ側データを削除（best-effort）
      - `alerts`（→ locations/deliveries/alert_recipients/reactions/revocations は CASCADE で削除）
      - `contacts`（→ deliveries(contact) は CASCADE）
      - `users`（public.users）
    - Supabase Auth Admin API で `auth.users/{id}` を削除。
    - 200で `{ ok: true }` を返す。

- スキーマ/制約（推奨）
  - 連鎖削除を確実にするため、以下を整備：
    - `contacts.user_id` / `alerts.user_id` → `users.id` は `ON DELETE CASCADE`（既定）
    - `locations.alert_id` / `deliveries.alert_id` / `alert_recipients.alert_id` / `reactions.alert_id` → `alerts.id` は `ON DELETE CASCADE`（既定）
    - （任意）`public.users.id` → `auth.users(id)` に `ON DELETE CASCADE` を付与しておくと、「Auth削除だけで全削除」が可能。

- 運用メモ
  - RLSはONにすることを推奨（WorkersはService Roleでバイパス）。
  - 直接SQLの実行は不要。アプリの「アカウント削除」からAPI経由で処理可能。

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

### GitHub Actions（iOS ビルド運用方針）

- 実行条件（軽量運用）
  - push / pull_request 時は iOS 関連変更のみで実行（paths: `apps/ios/**`, `.github/workflows/ios-build.yml`）。
  - 同一ブランチの重複実行は `concurrency` でキャンセル。
  - 通常は Debug-Dev（Simulator）のみビルドする「軽量ジョブ」を実行。
  - Dev/Stage/Prod 全環境のマトリクスビルドは週次スケジュールまたは手動実行時のみ。

- ビルド安定化
  - コードサイン無効化: `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`。
  - アーキ最小化: `ONLY_ACTIVE_ARCH=YES`（Simulator向け）。
  - シミュレータ端末は `xcodebuild -showdestinations` を解析し動的に解決（端末名/OSに依存しない）。

- Secrets/設定の扱い
  - iOS ビルドに必要な Secrets（環境ごと: dev/stage/prod）
    - `APP_BUNDLE_ID`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `OAUTH_REDIRECT_SCHEME`（未設定時 `kokosos`）、任意で `WEB_PUBLIC_BASE`。
  - CI 開始時に `Configs/Secrets-<Env>.xcconfig` を生成し、`SUPABASE_HOST` や `EMAIL_REDIRECT_*` を自動導出。
  - 署名チームなど共通値の include 先 `Configs/Secrets-Common.xcconfig` は CI で自動生成（空の `DEVELOPMENT_TEAM`）。
  - `apps/ios/Configs/Secrets-*.xcconfig` は Git 管理対象外（.gitignore）。

- 失敗時の診断／成果物
  - 失敗した場合のみ、整形ログ（`xcodebuild-*.log`）、生ログ（`xcodebuild-*-raw.log`）、`*.xcresult` をアーティファクトとして保存。
  - ログ抽出は日本語/英語のエラーパターンを拾って先頭50行＋末尾200行を表示。
  - ローカルで検証する場合、アーティファクトは `artifacts/` 以下に展開するが Git 管理外（.gitignore に登録）。

- コスト最適化の方針
  - iOS 変更がない限り CI を起動しない。
  - 週次マトリクスは必要に応じて停止し、手動実行のみに切替可能。
  - それでも不安定・高コストが続く場合は iOS CI を停止（削除）し、手元ビルド＋タグ/リリースの自動化のみを残す。

### Cloud 環境（dev/stage/prod）と SES

- Workers（API）デプロイ時は GitHub Environments の Secrets を Cloudflare Secrets に反映。
  - dev/stage/prod 共通（devにも適用）
    - `JWT_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `CORS_ALLOW_ORIGIN`, `WEB_PUBLIC_BASE`, `EMAIL_PROVIDER`（`ses` 推奨）
    - SES 連携: `SES_REGION`, `SES_ACCESS_KEY_ID`, `SES_SECRET_ACCESS_KEY`, `SES_SENDER_EMAIL`
  - `deploy-api.yml` が `wrangler secret put` で各環境に注入。

#### SES（メール）設定手順とIAMポリシー（kokosos.com）

目的
- 迷惑メール入りを避けつつ、環境ごとに安全に送信する。

手順（ap-northeast-1 の例）
- ドメイン認証（Easy DKIM）
  - SES → Verified identities → Create identity: Domain = `kokosos.com`, DKIM = Easy DKIM
  - SESが提示するDKIM CNAME 3件を Cloudflare DNS に追加（DNS only / グレー雲）
  - Identity の DKIM/Verification が Verified になるまで待機
- MAIL FROM（SPF整合）
  - SES → Verified identities → `kokosos.com` → Set MAIL FROM
  - 例) `bounce.kokosos.com`
  - 表示された `MX` と `TXT(SPF)` を Cloudflare DNS に追加（DNS only / グレー雲）
- DMARC（観測→段階強化）
  - Cloudflare DNS: TXT `_dmarc.kokosos.com` → `v=DMARC1; p=none; rua=mailto:dmarc@kokosos.com; fo=1`
  - 安定後に `p=quarantine` → `p=reject` を検討

IAM（送信専用ユーザーの例）
- ユーザー命名（例）
  - dev: `ses-sender-kokosos-dev`
  - stage: `ses-sender-kokosos-stage`
  - prod: `ses-sender-kokosos-prod`
- ポリシー（例: `ses-send-only-kokosos`）
  - ドメイン全体許可（Fromが `*@kokosos.com`）
  - `Resource` は SES アイデンティティARNに限定（ドメインと必要に応じて個別アドレス）

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSesSendFromKokososDomain",
      "Effect": "Allow",
      "Action": ["ses:SendEmail", "ses:SendRawEmail"],
      "Resource": [
        "arn:aws:ses:ap-northeast-1:<ACCOUNT_ID>:identity/kokosos.com",
        "arn:aws:ses:ap-northeast-1:<ACCOUNT_ID>:identity/noreply@kokosos.com"
      ],
      "Condition": {
        "StringLike": { "ses:FromAddress": "*@kokosos.com" }
      }
    }
  ]
}
```

備考
- 単一の差出人のみ許可する場合は `StringEquals` + `noreply@kokosos.com` を使用
- アイデンティティARNは SES > Verified identities の詳細に表示

Workers（環境ごと）
- Secrets（dev/stage/prod）
  - `EMAIL_PROVIDER=ses`
  - `SES_REGION=ap-northeast-1`
  - `SES_ACCESS_KEY_ID`, `SES_SECRET_ACCESS_KEY`（上記IAMユーザー）
  - `SES_SENDER_EMAIL=noreply@kokosos.com`
  - （診断時のみ）`EMAIL_DEBUG=true`（dev限定推奨）
- 反映: `npx wrangler deploy --env <env>` → `/_health` で `ok: true`

運用のポイント
- From を自社ドメインで統一（例: `noreply@kokosos.com`）
- DKIM/DMARC/MAIL FROM を整えてから本運用へ移行
- 迷惑メール入りの初期学習: 受信者側で「迷惑ではない」を実施
- 送信量増加は段階的に（ウォームアップ）

### Cloudflare Pages/Workers 構成（方式B: プロジェクト分割）

- 目的
  - Pages（Web）は dev/stage/prod でプロジェクトを分割し、各環境に独立したカスタムドメインを割り当てる。
  - Workers（API）は env ごとにルートを張り、環境別のカスタムドメインを使用する。

- 構成（推奨例）
  - Pages（Web）
    - dev: プロジェクト `kokosos-web-dev` → `app-dev.kokosos.com`
    - stage: プロジェクト `kokosos-web-stage` → `app-stage.kokosos.com`
    - prod: プロジェクト `kokosos-web` → `app.kokosos.com`
  - Workers（API）
    - dev: スクリプト `kokosos-api-dev` → ルート `api-dev.kokosos.com/*`
    - stage: スクリプト `kokosos-api-stage` → ルート `api-stage.kokosos.com/*`
    - prod: スクリプト `kokosos-api` → ルート `api.kokosos.com/*`

- DNS（Cloudflare DNS）
  - Pages 用（CNAME / Proxied 有効）
    - `app-dev.kokosos.com` → `kokosos-web-dev.pages.dev`
    - `app-stage.kokosos.com` → `kokosos-web-stage.pages.dev`
    - `app.kokosos.com` → `kokosos-web.pages.dev`
  - Workers 用（Custom Domain / Proxied 有効）
    - ルートを Workers に張る前提で、ダミー A `192.0.2.1`（または CNAME）でも可（最終的に Workers で終端）

- 割り当て手順（Pages）
  - 各 Pages プロジェクト > Custom domains > Add で上記ドメインを追加し、`Active` になるまで待機（証明書発行）。
  - 同一ホスト名を複数プロジェクト/環境に重複割当しない（混在の原因）。

- 割り当て手順（Workers）
  - `wrangler.toml` の対象 env に `route = "api-<env>.kokosos.com/*"` を設定。
  - `wrangler deploy --env <env>` で反映。
  - API トークン権限（最小）: Account→Workers Scripts: Edit、Zone→Zone: Read / Workers Routes: Edit。

- アプリ設定（整合）
  - Workers Secrets（環境別）
    - `CORS_ALLOW_ORIGIN`: `https://app-dev.kokosos.com` / `https://app-stage.kokosos.com` / `https://app.kokosos.com`
    - `WEB_PUBLIC_BASE`: 上記 Web ドメイン
  - iOS Info-*.plist（環境別）
    - `APIBaseURL`（または `APIBaseHost`/`APIBaseScheme`）を API ドメインに合わせる
    - `EmailRedirectBase`/`EmailRedirectHost` を Web ドメインに合わせる

- トラブルシュート
  - 期待と違うページが出る: Pages の Custom domains の紐付け先を確認し、不要なプロジェクトから Remove → 正しいプロジェクトに再割当。
  - `Active` にならない: DNS の CNAME（Proxied）と証明書の発行待ちを確認（数分〜十数分）。
  - pages.dev では表示できるが独自ドメインで不可: Redirect Rules / Bulk Redirect の干渉を確認。

#### API ドメイン設定手順（dev/stage/prod）

目的
- 環境ごとに `api-<env>.kokosos.com` を Cloudflare Workers へルーティングし、環境変数（Secrets）とCORS/WEB_PUBLIC_BASEを一致させる。

共通前提
- DNS は Cloudflare 管理（ネームサーバー移行済み）
- API トークン権限（最小）
  - Account → Workers Scripts: Edit
  - Zone(kokosos.com) → Zone: Read / Workers Routes: Edit

dev（api-dev.kokosos.com）
- DNS（Cloudflare DNS）
  - 方式A（推奨・Origin不要）: Type=A, Name=`api-dev`, Content=`192.0.2.1`, Proxy=ON
  - 方式B（CNAMEでも可）: Name=`api-dev`, Content=`任意ターゲット`, Proxy=ON
- Workers（wrangler.toml）
  - `[env.dev]` セクションに `route = "api-dev.kokosos.com/*"`
  - デプロイ: `cd apps/api-worker && npx wrangler deploy --env dev`
- Secrets（dev環境に投入）
  - 必須: `JWT_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
  - 推奨: `CORS_ALLOW_ORIGIN=https://app-dev.kokosos.com`, `WEB_PUBLIC_BASE=https://app-dev.kokosos.com`
- 動作確認
  - `https://api-dev.kokosos.com/_health` が `{ ok: true }` を返す
  - ダッシュボード > Workers > 対象スクリプト > Triggers > Custom domains に `api-dev.kokosos.com` が表示

stage（api-stage.kokosos.com）
- DNS（Cloudflare DNS）
  - Type=A, Name=`api-stage`, Content=`192.0.2.1`, Proxy=ON（またはCNAME, Proxy=ON）
- Workers（wrangler.toml）
  - `[env.stage]` セクションに `route = "api-stage.kokosos.com/*"`
  - デプロイ: `cd apps/api-worker && npx wrangler deploy --env stage`
- Secrets（stage環境に投入）
  - 必須: `JWT_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`（stage用のSupabase）
  - 推奨: `CORS_ALLOW_ORIGIN=https://app-stage.kokosos.com`, `WEB_PUBLIC_BASE=https://app-stage.kokosos.com`
- 動作確認
  - `https://api-stage.kokosos.com/_health` で確認

prod（api.kokosos.com）
- DNS（Cloudflare DNS）
  - Type=A, Name=`api`, Content=`192.0.2.1`, Proxy=ON（またはCNAME, Proxy=ON）
- Workers（wrangler.toml）
  - `[env.prod]` セクションに `route = "api.kokosos.com/*"`
  - デプロイ: `cd apps/api-worker && npx wrangler deploy --env prod`
- Secrets（prod環境に投入）
  - 必須: `JWT_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`（本番Supabase）
  - 推奨: `CORS_ALLOW_ORIGIN=https://app.kokosos.com`, `WEB_PUBLIC_BASE=https://app.kokosos.com`
- 動作確認
- `https://api.kokosos.com/_health` で確認

補足
- `workers_dev = true` を使えば、カスタムドメイン設定前に `*.workers.dev` で先に動作確認ができる（本番運用はルート方式を推奨）。
- 同じホスト名を複数の Worker や env に重複割当しない。

#### GitHub Actions（API デプロイ）環境・Secrets（dev/stage/prod）

ブランチ→Environment のマッピング（deploy-api.yml）
- dev ブランチ → Environment: `dev` → `wrangler deploy --env dev`
- stage ブランチ → Environment: `stage` → `wrangler deploy --env stage`
- main ブランチ → Environment: `prod` → `wrangler deploy --env prod`

GitHub Environments を 3 つ用意（dev / stage / prod）し、各 Environment に以下の Secrets を登録する。

必須（環境ごとに値を分ける）
- `CLOUDFLARE_API_TOKEN`: Account→Workers Scripts: Edit、Zone→Zone: Read / Workers Routes: Edit を付与したAPIトークン
- `CLOUDFLARE_ACCOUNT_ID`: Cloudflare Account ID
- `JWT_SECRET`: API 署名用シークレット
- `SUPABASE_URL`: 環境の Supabase プロジェクト URL
- `SUPABASE_SERVICE_ROLE_KEY`: 環境の Supabase Service Role Key（Workers のみで使用）

推奨（環境整合のため）
- `CORS_ALLOW_ORIGIN`
  - dev: `https://app-dev.kokosos.com`
  - stage: `https://app-stage.kokosos.com`
  - prod: `https://app.kokosos.com`
- `WEB_PUBLIC_BASE`
  - dev: `https://app-dev.kokosos.com`
  - stage: `https://app-stage.kokosos.com`
  - prod: `https://app.kokosos.com`
- メール送信（SES を使う場合）
  - `EMAIL_PROVIDER=ses`
  - `SES_REGION`, `SES_ACCESS_KEY_ID`, `SES_SECRET_ACCESS_KEY`, `SES_SENDER_EMAIL`

デプロイの流れ（CI 内）
1) `wrangler deploy --env <env>` でスクリプト公開＆Routes作成
2) `wrangler secret put ... --env <env>` で Secrets をWorkersに注入
3) `/ _health` 応答とダッシュボードの Triggers（Custom domains）で反映確認

CI トラブルシュート
- 10000 Authentication error（Routes作成に失敗）
  - `CLOUDFLARE_API_TOKEN` に Zone→Workers Routes: Edit / Zone: Read の権限が不足
- タイムアウト/522（`/_health` 到達不可）
  - DNS が Proxied（オレンジ雲）か、`wrangler.toml` の `route` が環境に入っているか確認
- `/_health` で `has.JWT_SECRET=false` 等
  - 対応する Secrets が未注入（ジョブ内の `wrangler secret put` が走っているか / 値が設定されているか）

チェックリスト（各環境）
- DNS: `api-<env>.kokosos.com` が Proxied で存在
- Workers: `[env.<env>].route = "api-<env>.kokosos.com/*"`
- Secrets: `JWT_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` が注入済み
- CORS/WEB_PUBLIC_BASE: `https://app-<env>.kokosos.com` に一致
- `/ _health` が `{ ok: true }` を返す

### API 公開とセキュリティ注意

- 公開ポリシー
  - API の DNS（`api.kokosos.com`/`api-dev.kokosos.com`）は公開して問題ない。重要なのは「認証必須の境界」を厳格にすること。
  - 本番/開発ともに `REQUIRE_AUTH_SENDER=true` を有効化し、送信者向けエンドポイントは常に Supabase Auth のトークン必須とする。
  - `CORS_ALLOW_ORIGIN` は許可したオリジンのみに限定（例: `https://app.kokosos.com`、dev は `https://app-dev.kokosos.com`）。ワイルドカード（`*`）は使用しない。
  - `JWT_SECRET` は十分強い値を設定。`SUPABASE_SERVICE_ROLE_KEY` は Workers Secrets のみ（クライアントへ露出しない）。

- エンドポイント公開範囲（前提）
  - 公開OK（署名付きJWTが必須）: `/public/alert/:token`, `/public/alert/:token/stream`, `/public/alert/:token/react`, `/public/verify/:token`。
  - 認証必須（送信者）: `/alert/*`（start/update/stop/extend/revoke）, `/contacts/*`（list/bulk_upsert/send_verify）。

- 注意・制限（必須）
  - 診断系 `_diag/*` は本番で無効化または IP 制限・環境フラグで閉じる。
  - `_health` は必要最小の情報のみ返す（必要に応じて簡易Authや出力削減を検討）。
  - レート制限・Bot対策を有効化（Cloudflare WAF / Bot Fight）。特に `/public/*` やメール送信系は厳しめのしきい値を推奨。
  - ログに PII/トークンを出力しない。出力時は必ずマスク（既定の `_health` はマスク済み）。
  - TLS/セキュリティヘッダは維持（HSTS, CSP, X-Frame-Options など既定値を変更しない）。
  - 検索避け: 公開リンクのクロール抑止が必要な場合は `X-Robots-Tag: noindex` を適用（必要性に応じて運用で判断）。

---

### ドメイン運用（PRプレビューなし方針）

- 命名と役割（Custom Domain; PRプレビューは使わない）
  - ルートサイト（紹介用）
    - 本番: `https://kokosos.com`
    - ステージ: `https://site-stage.kokosos.com`
    - 開発: `https://site-dev.kokosos.com`
  - Webアプリ（受信者向けApp）
    - 本番: `https://app.kokosos.com`
    - ステージ: `https://app-stage.kokosos.com`
    - 開発: `https://app-dev.kokosos.com`
  - API（Workers）
    - 本番: `https://api.kokosos.com`
    - ステージ: `https://api-stage.kokosos.com`
    - 開発: `https://api-dev.kokosos.com`
  - 共有リンク短縮（任意）
    - 本番: `https://s.kokosos.com`
    - ステージ: `https://s-stage.kokosos.com`
    - 開発: `https://s-dev.kokosos.com`

- 運用ルール
  - ルートサイト（apex `kokosos.com`）は紹介専用。アプリは常に `app.*` に配置（混同防止）。
  - dev/stage は `-dev / -stage` のサブドメインで Pages / Workers に割当。
  - CORS / `WEB_PUBLIC_BASE` は環境ごとに一致させる（例: dev は `app-dev.kokosos.com`）。
  - PRプレビューは使用しない（dev/stage のブランチ反映で確認）。

### デプロイ運用（CI）

- ルートサイト（kokosos-root; sites/root）
  - `.github/workflows/deploy-root.yml`
  - push: `dev` → プレビュー（Custom Domain: `site-dev.kokosos.com`）
  - push: `stage` → プレビュー（Custom Domain: `site-stage.kokosos.com`）
  - push: `main` → 本番（Custom Domain: `kokosos.com`）
  - pull_request トリガーは無効（PRではデプロイしない）

- Web（Pages） / API（Workers）
  - 各ワークフローは差分検知で必要時のみ実行。dev/stage/main の各ブランチで該当環境へ反映。

### Cloudflare Pages の Custom Domain 割当手順（ルートサイト例）

前提: `kokosos.com` の DNS が Cloudflare 管理（ネームサーバー移管済み）。

1) プロジェクトを用意
  - Pages > Projects > `kokosos-root`（既存がなければ作成; Production Branch は `main`）。

2) 本番ドメイン（apex）を割当
  - `kokosos-root` > Custom domains > Add: `kokosos.com` を追加。
  - 案内に従って DNS レコード（CNAME フラットニング）が自動追加され、SSL 証明書が有効化されるまで待機（Active になるまで数分〜数十分）。
  - （任意）`www.kokosos.com` から apex へのリダイレクトを構成（Pages Redirects または Cloudflare Bulk Redirects）。

3) プレビュー用サブドメインを割当
  - 同画面の Preview deployments で「Add」→ `site-dev.kokosos.com` を追加し、Branch に `dev` を指定。
  - 同様に `site-stage.kokosos.com` を追加し、Branch に `stage` を指定。
  - いずれも Cloudflare が CNAME を自動追加し、Active 状態で利用可能に。

4) 動作確認
  - `dev` ブランチに push → `https://site-dev.kokosos.com` が更新される（CI が自動デプロイ）。
  - `stage` ブランチに push → `https://site-stage.kokosos.com` が更新される。
  - `main` ブランチに push → `https://kokosos.com` が本番更新される。

（参考）アプリ / API の Custom Domain 設定
  - Web（Pages）: それぞれの Pages プロジェクトに `app-dev.* / app-stage.* / app.*` を Custom Domain 追加。
  - API（Workers）: 対象 Worker の Triggers > Custom Domains で `api-dev.* / api-stage.* / api.*` を追加。
  - Secrets / CORS / `WEB_PUBLIC_BASE` をドメインに合わせて更新し、`/_health` で反映確認。


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
