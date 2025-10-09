KokoSOS Monorepo (MVP skeleton)

Overview
- Requirements spec: docs/requirements.md
- iOS app triggers alerts; this repo provides the API, web receiver, and DB schema.
- Stack: Cloudflare Workers (API), Next.js 14 (receiver web), Supabase Postgres (DB), AWS SES (email).
 - Auth (sender): Supabase Auth (Email/Password, Apple, Google, Facebook)

Structure
- apps/api-worker: Cloudflare Workers API with JWT and SSE skeleton.
- apps/web: Next.js App Router receiver at `/s/[token]`.
- apps/ios: UIKitベースのiOSアプリ（XcodeGenで生成）
- db/schema.sql: Postgres schema for users, contacts, alerts, locations, deliveries, revocations.
- .env.example: Required env vars for local/dev configuration.
- .github/workflows: GitHub Actions for Workers/Pages デプロイ（dev/stage/prod）。

Quickstart
- Docker: `docker-compose up --build` then open `http://localhost:3000`.
- API (non-Docker): install Wrangler and run `wrangler dev` inside `apps/api-worker`.
- Web (non-Docker): run `next dev` inside `apps/web` after installing dependencies.
- DB: apply `db/schema.sql` to Supabase（クラウド or Supabase CLIでローカル起動）。

Environment
- Copy `.env.example` to `.env` in each app as needed. Register secrets in your platform (Wrangler, Cloudflare Pages, Supabase, GitHub Actions).
 - API auth (optional → recommended):
   - `SUPABASE_URL=https://<project-ref>.supabase.co`
   - `SUPABASE_JWKS_URL=https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json` (省略時は自動導出)
   - `REQUIRE_AUTH_SENDER=true` を有効にすると `/alert/*` は Authorization: Bearer <Supabase access_token> を必須に

Docker notes
- `docker-compose` は API(8787) と Web(3000) を起動。ブラウザは `http://localhost:3000` へアクセスし、クライアントJSが `http://localhost:8787` に直接アクセスします。
- CORS は API 側で `CORS_ALLOW_ORIGIN=http://localhost:3000` を許可済み（環境変数で変更可）。
- メールは `mailhog` を同梱（任意）。SMTP 送信を `localhost:1025` に向けると `http://localhost:8025` で閲覧可能。

GitHub デプロイ（Cloudflare dev/stage/prod）
- ブランチ: `dev` → dev, `stage` → stage, `main` → prod。
- Workers: `.github/workflows/deploy-api.yml:1` が `wrangler deploy --env <env>` を実行。
- Pages(Next.js): `.github/workflows/deploy-web.yml:1` が `@cloudflare/next-on-pages` でビルドし Pages へデプロイ。
- Pages プロジェクト名: `kokosos-web-<env>`（例: dev→`kokosos-web-dev`）。Cloudflare で3プロジェクト作成を推奨。
- GitHub Environments: `dev`, `stage`, `prod` を作成し、各環境に以下のシークレットを登録:
  - `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`
  - API用: `JWT_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SES_*`, `CORS_ALLOW_ORIGIN`
  - Web用（必要に応じて）: `NEXT_PUBLIC_API_BASE` 等はPagesの「環境変数」側で設定推奨

iOS CI（任意）
- Workflow: `.github/workflows/ios-build.yml` が Dev/Stage/Prod をマトリクスでビルド
- 環境ごと（Environments: dev/stage/prod）に以下のSecretsを登録:
  - `SUPABASE_URL`, `SUPABASE_ANON_KEY`（`OAUTH_REDIRECT_SCHEME`は未設定時 `kokosos`）
- CIは `apps/ios/Configs/Secrets-<Env>.xcconfig` を生成し、`xcodegen generate` → `xcodebuild` を実行

Cloudflare 側準備
- Workers: wrangler は環境ごとに `name` を分離（`apps/api-worker/wrangler.toml:1`）。
- Pages: `kokosos-web-dev`, `kokosos-web-stage`, `kokosos-web-prod` の3プロジェクトを作成（同一リポ参照でも可）。
- ドメイン/ルーティング: 各環境のCORS許可元をAPI側の `CORS_ALLOW_ORIGIN` に反映。

Endpoints (API)
- POST `/alert/start`: Start sharing, returns `shareToken` and alert metadata.
- POST `/alert/:id/update`: Periodic location update.
- POST `/alert/:id/stop`: Stop or arrived.
- POST `/alert/:id/extend`: Extend max_duration (server clamps within 5m–6h).
- POST `/alert/:id/revoke`: Revoke link immediately.
- GET `/public/alert/:token`: Initial state for receiver.
- GET `/public/alert/:token/stream`: SSE stream for live updates.
- POST `/public/alert/:token/react`: Preset reaction from receiver.

Auth (sender)
- Use Supabase Auth on clients (iOS/Android/Web) to obtain `access_token`, then call `/alert/*` with `Authorization: Bearer <token>`.
- Workers verifies the token via Supabase JWKS (RS256) and uses `sub` as `user_id`.

Security
- JWT HS256 with `alert_id`, `contact_id`, `scope`, `exp` (≤24h).
- Revocations checked to immediately invalidate tokens.
- Security headers set: HSTS, Referrer-Policy, X-Frame-Options, CSP (nonce-based skeleton).

- Email sending uses AWS SES (local dev may use MailHog).
- SSE broadcasting is stubbed; connect to storage/pubsub as you wire Supabase/Workers Durable Objects.

Hardening (optional but recommended)
- Turnstile (Cloudflare CAPTCHA)
  - Server: set `TURNSTILE_SECRET_KEY` and `REQUIRE_TURNSTILE_PUBLIC=true` on Workers. Optionally set `APP_SCHEMES` (CSV, e.g., `kokosos,kokosos-dev`) to allow native app deep-link callbacks.
  - Client: include Turnstile widget and send token as `turnstile_token` (or `cf-turnstile-response`) in body to these endpoints: `POST /auth/email/reset`, `/auth/email/magic`, `/auth/signup`.
  - If verification fails, the server rejects without sending email.
- Rate limiting (Workers Durable Object)
  - Built-in fixed-window counters via a `RateLimiter` Durable Object.
  - Applied to the public auth email endpoints (per-IP and per-email). Default thresholds:
    - Reset/Magic: IP 5/min, Email 5/hour
    - SignUp: IP 3/5min, Email 3/hour
  - For additional protection, also enable Cloudflare WAF/Rate Limiting rules at the edge.
- iOS（UIKit / XcodeGen）
- 生成: `brew install xcodegen` 後、`cd apps/ios && xcodegen generate && open KokoSOS.xcodeproj`
- ビルド構成: Debug/Release × Dev/Stage/Prod（6構成）。`apps/ios/Configs/*.xcconfig`で `API_BASE_URL` を環境ごとに設定。
- 実行に必要な権限: 位置情報（フォアグラウンド/常時）
- 起動フロー: アプリ起動 → 3秒カウントダウン → `/alert/start` へ初回位置とバッテリーを送信 → shareToken表示
- 実機テスト時のAPI接続: デバイスから`localhost`は使えません。アプリ内「設定 > APIベースURL」に `http://<MacのIP>:8787`（ローカル開発）または公開APIのURLを入力してください（未設定時はInfo.plistの`APIBaseURL`/`APIBaseHost`を使用）。
- xcconfigの`//`コメント問題の回避: `API_BASE_URL`に`https://...`を書くと`//`以降がコメントとして無視される場合があります。Secrets-*.xcconfig では `API_BASE_HOST=kokosos-api-<env>.<your>.workers.dev` とし、`API_BASE_SCHEME=https` を併用してください。コード側で `APIBaseHost` として解決します。

**iOS 接続設定/仕様（追記）**
- 呼び出すAPI（Cloudflare Workers）
  - 送信者用: `POST /alert/start|:id/update|:id/stop|:id/extend|:id/revoke`
  - 公開用: `GET /public/alert/:token`, `GET /public/alert/:token/stream`, `POST /public/alert/:token/react`
  - 認証: `Authorization: Bearer <Supabase access_token>`（`REQUIRE_AUTH_SENDER=true`時必須）
- iOSの接続先の決定優先度（APIClient）
  1) アプリ内「設定 > APIベースURL」の上書き値（http/https かつ host 必須のときのみ有効）
  2) Info.plistの`APIBaseURL`（有効URLのとき）
  3) Info.plistの`APIBaseHost` + `APIBaseScheme`（有効hostのとき）
  4) フォールバック: `http://localhost:8787`（Dev向け）
- Info/xcconfigキー（Stage/Prodはhttps推奨）
  - Info.plist: `APIBaseURL`, `APIBaseHost`, `APIBaseScheme`
  - xcconfig: `API_BASE_URL`, `API_BASE_HOST`, `API_BASE_SCHEME`（Secrets-*.xcconfigで上書き可）
- 既知の注意点と対処
  - 実機は`localhost`不可。公開ドメインまたはLAN IPを指定。
  - `API_BASE_URL`に`https://...`を直書きすると`//`以降がコメント扱いになるケースあり → `API_BASE_HOST`/`API_BASE_SCHEME`を使用。
  - エンドポイントURLはパスセグメントで結合（先頭`/`は付けない）。`/alert/start`を`appendingPathComponent("/alert/start")`に渡すと`%2Falert%2Fstart`になり404になるため修正済み。
- エラーハンドリング（アプリ表示）
  - ホスト解決失敗: 「設定>APIベースURL」を促すメッセージ（現在のURLを併記）
  - サーバー非2xx: `サーバーエラー(ステータス)` とレスポンスJSONの`error/detail`を整形表示（切り分け容易）
- トラブルシュート
  - APIヘルス: `GET https://<APIホスト>/_health`（`REQUIRE_AUTH_SENDER`, `SUPABASE_URL_preview` 等を確認）
  - 401 invalid_token: Workersの`SUPABASE_URL`がiOSのプロジェクトと不一致/`REQUIRE_AUTH_SENDER`設定の確認
  - 500 server_misconfig: Workersの`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`未設定
  - 400 invalid_location: `lat/lng`未送信（通常は位置取得完了後に送信）

Push notifications (FCM)
- Server uses Firebase Cloud Messaging (HTTP v1) to deliver push notifications to the sender’s devices when the receiver reacts (e.g., presses “OK”).
- Requirements:
  - Configure these env vars on the API (Workers): `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY` (see `.env.example`).
  - iOS app must include a valid `GoogleService-Info.plist` for the environment and obtain an FCM token.
  - The signed-in iOS app registers the FCM token via `POST /devices/register` (handled automatically in the app).
- Diagnostics:
  - `GET /_health` now shows FCM presence flags.
  - Pressing a reaction on the receiver page calls `POST /public/alert/:token/react` and the response JSON includes a `push` field: `sent`|`skipped`|`error`.
