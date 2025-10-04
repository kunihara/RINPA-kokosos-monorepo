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
- iOS（UIKit / XcodeGen）
- 生成: `brew install xcodegen` 後、`cd apps/ios && xcodegen generate && open KokoSOS.xcodeproj`
- ビルド構成: Debug/Release × Dev/Stage/Prod（6構成）。`apps/ios/Configs/*.xcconfig`で `API_BASE_URL` を環境ごとに設定。
- 実行に必要な権限: 位置情報（フォアグラウンド/常時）
- 起動フロー: アプリ起動 → 3秒カウントダウン → `/alert/start` へ初回位置とバッテリーを送信 → shareToken表示
