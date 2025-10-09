export interface Env {
  JWT_SECRET: string
  SUPABASE_URL?: string
  SUPABASE_SERVICE_ROLE_KEY?: string
  SUPABASE_JWKS_URL?: string
  REQUIRE_AUTH_SENDER?: string
  REQUIRE_TURNSTILE_PUBLIC?: string
  SES_REGION?: string
  SES_ACCESS_KEY_ID?: string
  SES_SECRET_ACCESS_KEY?: string
  SES_SENDER_EMAIL?: string
  CORS_ALLOW_ORIGIN?: string
  WEB_PUBLIC_BASE?: string
  EMAIL_PROVIDER?: string
  // dev専用デバッグ用フラグ（true でマスク付きログを出力）
  EMAIL_DEBUG?: string
  DEFAULT_USER_EMAIL?: string
  ALERT_HUB: DurableObjectNamespace
  RATE_LIMITER: DurableObjectNamespace
  // FCM (HTTP v1) credentials for push notifications
  FCM_PROJECT_ID?: string
  FCM_CLIENT_EMAIL?: string
  FCM_PRIVATE_KEY?: string
  // Security helpers
  TURNSTILE_SECRET_KEY?: string
  APP_SCHEMES?: string
  RATE_LIMIT_OFF?: string
}

type Method = 'GET' | 'POST'

type RouteHandler = (c: { req: Request; env: Env; ctx: ExecutionContext; params: Record<string, string> }) => Promise<Response>

const json = (data: unknown, init: ResponseInit = {}) =>
  new Response(JSON.stringify(data), {
    status: 200,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...securityHeaders(),
      ...init.headers,
    },
    ...init,
  })

const nowSec = () => Math.floor(Date.now() / 1000)

async function verifyJwtHs256(token: string, secret: string): Promise<Record<string, unknown> | null> {
  const parts = token.split('.')
  if (parts.length !== 3) return null
  const [hB64, pB64, sB64] = parts
  const enc = new TextEncoder()
  const data = `${hB64}.${pB64}`
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify'])
  const sig = base64urlToUint8Array(sB64)
  const ok = await crypto.subtle.verify('HMAC', key, sig, enc.encode(data))
  if (!ok) return null
  const payloadRaw = new TextDecoder().decode(base64urlToUint8Array(pB64))
  const payload = JSON.parse(payloadRaw) as Record<string, unknown>
  const exp = typeof payload.exp === 'number' ? payload.exp : undefined
  if (exp && nowSec() > exp) return null
  return payload
}

function base64urlToUint8Array(s: string): Uint8Array {
  s = s.replace(/-/g, '+').replace(/_/g, '/')
  const pad = s.length % 4
  if (pad) s += '='.repeat(4 - pad)
  const bin = atob(s)
  const bytes = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
  return bytes
}

function securityHeaders(): HeadersInit {
  return {
    'Referrer-Policy': 'no-referrer',
    'X-Frame-Options': 'DENY',
    'X-Content-Type-Options': 'nosniff',
    'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
    'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
  }
}

function corsHeaders(origin?: string): HeadersInit {
  const allow = origin || '*'
  return {
    'Access-Control-Allow-Origin': allow,
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
    'Access-Control-Max-Age': '600',
  }
}

// ---- Turnstile verification (optional)
async function verifyTurnstile(env: Env, token?: string, ip?: string): Promise<boolean> {
  if (!env.REQUIRE_TURNSTILE_PUBLIC || env.REQUIRE_TURNSTILE_PUBLIC.toLowerCase() !== 'true') return true
  if (!env.TURNSTILE_SECRET_KEY) return false
  if (!token) return false
  const form = new URLSearchParams()
  form.set('secret', env.TURNSTILE_SECRET_KEY)
  form.set('response', token)
  if (ip) form.set('remoteip', ip)
  const res = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', { method: 'POST', body: form })
  if (!res.ok) return false
  const j = await res.json().catch(() => null) as any
  return Boolean(j && j.success)
}

// ---- Simple rate limit helper via Durable Object
async function rateLimitCheck(env: Env, key: string, limit: number, windowSec: number): Promise<boolean> {
  if ((env.RATE_LIMIT_OFF || '').toLowerCase() === 'true') return true
  try {
    const stub = env.RATE_LIMITER.get(env.RATE_LIMITER.idFromName(key))
    const res = await stub.fetch(`https://rl/check?limit=${limit}&window=${windowSec}`)
    if (!res.ok) return true // fail-open to avoid false negatives
    const j = await res.json().catch(() => null) as any
    return Boolean(j && j.allow)
  } catch {
    return true
  }
}

function notFound() {
  return new Response('Not Found', { status: 404, headers: securityHeaders() })
}

function methodNotAllowed() {
  return new Response('Method Not Allowed', { status: 405, headers: securityHeaders() })
}

function parsePath(req: Request) {
  const url = new URL(req.url)
  return url.pathname
}

async function withJwtFromPathToken(req: Request, env: Env, token: string) {
  const payload = await verifyJwtHs256(token, env.JWT_SECRET)
  if (!payload) return null
  return payload
}

const routes: Array<{ method: Method; pattern: RegExp; handler: RouteHandler }> = [
  { method: 'GET', pattern: /^\/_health$/, handler: handleHealth },
  { method: 'GET', pattern: /^\/_diag\/alert\/([^/]+)$/, handler: handleDiag },
  { method: 'POST', pattern: /^\/_diag\/alert\/([^/]+)\/publish$/, handler: handleDiagPublish },
  // Diag helpers by token (dev support)
  { method: 'GET', pattern: /^\/_diag\/resolve\/([^/]+)$/, handler: handleDiagResolveToken },
  { method: 'GET', pattern: /^\/_diag\/alert\/by-token\/([^/]+)$/, handler: handleDiagAlertByToken },
  { method: 'POST', pattern: /^\/_diag\/alert\/by-token\/([^/]+)\/publish$/, handler: handleDiagAlertPublishByToken },
  { method: 'GET', pattern: /^\/_diag\/whoami$/, handler: handleWhoAmI },
  // Contacts (sender auth required)
  { method: 'GET', pattern: /^\/contacts$/, handler: handleContactsList },
  { method: 'POST', pattern: /^\/contacts\/bulk_upsert$/, handler: handleContactsBulkUpsert },
  { method: 'POST', pattern: /^\/contacts\/([^/]+)\/send_verify$/, handler: handleContactSendVerify },
  // Devices (FCM)
  { method: 'POST', pattern: /^\/devices\/register$/, handler: handleDevicesRegister },
  { method: 'POST', pattern: /^\/devices\/unregister$/, handler: handleDevicesUnregister },
  // Profile (avatar)
  { method: 'POST', pattern: /^\/profile\/avatar\/upload-url$/, handler: handleAvatarUploadURL },
  { method: 'POST', pattern: /^\/profile\/avatar\/upload$/, handler: handleAvatarUpload },
  { method: 'POST', pattern: /^\/profile\/avatar\/commit$/, handler: handleAvatarCommit },
  // Verify (public)
  { method: 'GET', pattern: /^\/public\/verify\/([^/]+)$/, handler: handleVerifyContact },
  // Account deletion
  { method: 'DELETE', pattern: /^\/account$/, handler: handleAccountDelete },
  { method: 'POST', pattern: /^\/alert\/start$/, handler: handleAlertStart },
  // accept UUIDs with hyphens or any non-slash segment
  { method: 'POST', pattern: /^\/alert\/([^/]+)\/update$/, handler: handleAlertUpdate },
  { method: 'POST', pattern: /^\/alert\/([^/]+)\/stop$/, handler: handleAlertStop },
  { method: 'POST', pattern: /^\/alert\/([^/]+)\/extend$/, handler: handleAlertExtend },
  { method: 'POST', pattern: /^\/alert\/([^/]+)\/revoke$/, handler: handleAlertRevoke },
  { method: 'GET', pattern: /^\/public\/alert\/([^/]+)$/, handler: handlePublicAlert },
  { method: 'GET', pattern: /^\/public\/alert\/([^/]+)\/stream$/, handler: handlePublicAlertStream },
  { method: 'GET', pattern: /^\/public\/alert\/([^/]+)\/locations$/, handler: handlePublicAlertLocations },
  { method: 'POST', pattern: /^\/public\/alert\/([^/]+)\/react$/, handler: handlePublicAlertReact },
  // Auth emails (generate + send via provider)
  { method: 'POST', pattern: /^\/auth\/email\/send$/, handler: handleAuthEmailSend },
  // Public endpoint for password reset email (no admin auth; return generic response to avoid user enumeration)
  { method: 'POST', pattern: /^\/auth\/email\/reset$/, handler: handleAuthEmailResetPublic },
  // Public endpoint: magic link sign-in
  { method: 'POST', pattern: /^\/auth\/email\/magic$/, handler: handleAuthEmailMagicPublic },
  // Authed endpoints: reauth and change email (current/new)
  { method: 'POST', pattern: /^\/auth\/email\/reauth$/, handler: handleAuthEmailReauth },
  { method: 'POST', pattern: /^\/auth\/email\/change$/, handler: handleAuthEmailChangeEmail },
  // Public endpoint: email/password sign-up via Admin + confirmation email
  { method: 'POST', pattern: /^\/auth\/signup$/, handler: handleAuthSignupPublic },
  // Ops (admin-only): delete unconfirmed user by email
  { method: 'POST', pattern: /^\/_diag\/auth\/cleanup_unconfirmed$/, handler: handleAuthDiagCleanupUnconfirmed },
]

async function handleHealth({ env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const mask = (v?: string) => (v ? `${v.slice(0, 4)}…(${v.length})` : null)
  const body = {
    ok: true,
    has: {
      JWT_SECRET: !!env.JWT_SECRET,
      SUPABASE_URL: !!env.SUPABASE_URL,
      SUPABASE_SERVICE_ROLE_KEY: !!env.SUPABASE_SERVICE_ROLE_KEY,
      FCM_PROJECT_ID: !!env.FCM_PROJECT_ID,
      FCM_CLIENT_EMAIL: !!env.FCM_CLIENT_EMAIL,
      FCM_PRIVATE_KEY: !!env.FCM_PRIVATE_KEY,
    },
    env: {
      CORS_ALLOW_ORIGIN: env.CORS_ALLOW_ORIGIN || null,
      WEB_PUBLIC_BASE: env.WEB_PUBLIC_BASE || null,
      EMAIL_PROVIDER: env.EMAIL_PROVIDER || null,
      DEFAULT_USER_EMAIL: env.DEFAULT_USER_EMAIL || null,
      SUPABASE_URL_preview: env.SUPABASE_URL || null,
      SUPABASE_SERVICE_ROLE_KEY_preview: env.SUPABASE_SERVICE_ROLE_KEY ? `${(env.SUPABASE_SERVICE_ROLE_KEY as string).slice(0,4)}…` : null,
      SUPABASE_JWKS_URL: env.SUPABASE_JWKS_URL || (env.SUPABASE_URL ? `${env.SUPABASE_URL.replace(/\/$/, '')}/auth/v1/.well-known/jwks.json` : null),
      REQUIRE_AUTH_SENDER: env.REQUIRE_AUTH_SENDER || 'false',
      FCM_PROJECT_ID_preview: env.FCM_PROJECT_ID || null,
      FCM_CLIENT_EMAIL_preview: env.FCM_CLIENT_EMAIL ? `${(env.FCM_CLIENT_EMAIL as string).slice(0,6)}…` : null,
      FCM_PRIVATE_KEY_present: env.FCM_PRIVATE_KEY ? true : false,
    },
  }
  return json(body)
}

async function handleDiag({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const m = req.url.match(/\/_diag\/alert\/([^/]+)/)
  if (!m) return notFound()
  const id = m[1]
  const stub = env.ALERT_HUB.get(env.ALERT_HUB.idFromName(id))
  const res = await stub.fetch('https://do/diag')
  return new Response(await res.text(), { status: res.status, headers: { 'content-type': 'application/json' } })
}

async function handleDiagPublish({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const m = req.url.match(/\/_diag\/alert\/([^/]+)\/publish/)
  if (!m) return notFound()
  const id = m[1]
  const stub = env.ALERT_HUB.get(env.ALERT_HUB.idFromName(id))
  const body = await req.text().catch(() => '')
  const payload = body || JSON.stringify({ type: 'diagnostic', ts: Date.now() })
  const res = await stub.fetch('https://do/publish', { method: 'POST', body: payload })
  return new Response(JSON.stringify({ ok: res.ok }), { headers: { 'content-type': 'application/json' } })
}

// ---- Dev helper: resolve a public token to payload (alert_id/contact_id)
async function handleDiagResolveToken({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const m = req.url.match(/\/_diag\/resolve\/([^/]+)/)
  if (!m) return notFound()
  const token = decodeURIComponent(m[1])
  const payload = await verifyJwtHs256(token, env.JWT_SECRET)
  if (!payload) return json({ ok: false, error: 'invalid_token' }, { status: 400 })
  const out: any = { ok: true }
  for (const k of ['alert_id', 'contact_id', 'scope', 'exp']) {
    if (k in payload) (out as any)[k] = (payload as any)[k]
  }
  return json(out)
}

async function handleDiagAlertByToken({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const m = req.url.match(/\/_diag\/alert\/by-token\/([^/]+)/)
  if (!m) return notFound()
  const token = decodeURIComponent(m[1])
  const payload = await verifyJwtHs256(token, env.JWT_SECRET)
  if (!payload) return json({ ok: false, error: 'invalid_token' }, { status: 400 })
  const alertId = String((payload as any).alert_id || '')
  if (!alertId) return json({ ok: false, error: 'no_alert_id' }, { status: 400 })
  const stub = env.ALERT_HUB.get(env.ALERT_HUB.idFromName(alertId))
  const res = await stub.fetch('https://do/diag')
  const txt = await res.text()
  return new Response(txt, { status: res.status, headers: { 'content-type': 'application/json' } })
}

async function handleDiagAlertPublishByToken({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const m = req.url.match(/\/_diag\/alert\/by-token\/([^/]+)\/publish/)
  if (!m) return notFound()
  const token = decodeURIComponent(m[1])
  const payload = await verifyJwtHs256(token, env.JWT_SECRET)
  if (!payload) return json({ ok: false, error: 'invalid_token' }, { status: 400 })
  const alertId = String((payload as any).alert_id || '')
  if (!alertId) return json({ ok: false, error: 'no_alert_id' }, { status: 400 })
  const stub = env.ALERT_HUB.get(env.ALERT_HUB.idFromName(alertId))
  const body = JSON.stringify({ type: 'diagnostic', via: 'by-token', ts: Date.now() })
  const r = await stub.fetch('https://do/publish', { method: 'POST', body })
  return json({ ok: r.ok })
}

// Quick diagnostic: who am I according to Authorization header?
async function handleWhoAmI({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const authz = req.headers.get('authorization') || req.headers.get('Authorization') || ''
  const m = authz.match(/^Bearer\s+(.+)$/i)
  const token = m ? m[1] : ''
  const primary = await getSenderFromAuth(req, env)
  const out: any = { ok: primary.ok, via: primary.ok ? 'jwks' : 'jwks_failed', status: (primary as any).status || 200 }
  if (primary.ok) out.userId = (primary as any).userId
  if (!primary.ok && token) {
    const fb = await fetchSupabaseUser(env, token)
    out.fallback = { ok: fb.ok, userId: fb.userId || null }
  }
  return json(out)
}

async function handleAlertStart({ req, env, ctx }: Parameters<RouteHandler>[0]): Promise<Response> {
  // Prefer JWT (JWKS) auth, then fall back to Supabase /auth/v1/user
  const authz = req.headers.get('authorization') || req.headers.get('Authorization') || ''
  const primary = await getSenderFromAuth(req, env)
  let userId: string | null = primary.ok ? (primary as any).userId ?? null : null
  if (!userId) {
    try {
      const m = authz.match(/^Bearer\s+(.+)$/i)
      const token = m ? m[1] : ''
      if (token) {
        const supa = await fetchSupabaseUser(env, token)
        if (supa.ok && supa.userId) userId = supa.userId
      }
    } catch {}
  }
  if (!userId) {
    // As a last resort for dev environments only, optionally ensure a default user
    const sbDev = supabase(env)
    if (sbDev && env.DEFAULT_USER_EMAIL) {
      try { userId = await ensureDefaultUserId(sbDev, env) } catch {}
    }
  }
  if (!userId) return json({ error: 'unauthorized', detail: 'invalid_sender' }, { status: primary.ok ? 401 : (primary as any).status || 401 })
  const body = await req.json().catch(() => null)
  if (!body) return json({ error: 'invalid_json' }, { status: 400 })
  const initial = {
    lat: body.lat as number | undefined,
    lng: body.lng as number | undefined,
    accuracy_m: body.accuracy_m as number | undefined,
    battery_pct: body.battery_pct as number | undefined,
    type: (body.type as string | undefined) || 'emergency',
    max_duration_sec: (body.max_duration_sec as number | undefined) ?? 3600,
    recipients: (Array.isArray(body.recipients) ? (body.recipients as string[]) : [])
  }
  if (typeof initial.lat !== 'number' || typeof initial.lng !== 'number') return json({ error: 'invalid_location' }, { status: 400 })
  // Require explicit recipients (privacy-by-default)
  if (!initial.recipients || initial.recipients.length === 0) return json({ error: 'no_recipients' }, { status: 400 })
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  // Ensure user row exists and get id
  await ensureUserExists(sb, userId)
  // Sanitize max duration (server-side clamp). Allow 5 minutes to 6 hours.
  const clampedMax = Math.min(6 * 3600, Math.max(5 * 60, initial.max_duration_sec))
  const alertRes = await sb.insert('alerts', {
    user_id: userId,
    type: initial.type,
    status: 'active',
    max_duration_sec: clampedMax,
  })
  if (!alertRes.ok) return json({ error: 'db_error', detail: alertRes.error }, { status: 500 })
  const alert = alertRes.data[0]
  const alertId: string = alert.id
  const startedAt: string = alert.started_at
  // Insert initial location
  await sb.insert('locations', {
    alert_id: alertId,
    lat: initial.lat,
    lng: initial.lng,
    accuracy_m: initial.accuracy_m ?? null,
    battery_pct: initial.battery_pct ?? null,
    captured_at: startedAt,
  })
  const shareToken = await signJwtHs256({ alert_id: alertId, scope: 'viewer', exp: nowSec() + 24 * 3600 }, env.JWT_SECRET)
  // Resolve recipients strictly (verified only)
  const norm = (s: string) => s.trim().toLowerCase()
  const requested = initial.recipients.map(norm).filter((e: string) => /.+@.+\..+/.test(e))
  if (requested.length === 0) return json({ error: 'no_recipients' }, { status: 400 })
  const list2 = await sb.select('contacts', 'id,email,verified_at', `user_id=eq.${encodeURIComponent(userId)}&email=in.(${requested.map(encodeURIComponent).join(',')})`)
  const rows = (list2.ok ? (list2.data as any[]) : [])
  const byEmail = new Map<string, any>(rows.map((r) => [norm(String(r.email)), r]))
  const invalid: string[] = []
  const recipients: { contact_id: string; email: string }[] = []
  for (const e of requested) {
    const row = byEmail.get(e)
    if (!row || !row.verified_at) invalid.push(e)
    else recipients.push({ contact_id: String(row.id), email: e })
  }
  if (invalid.length > 0) return json({ error: 'invalid_recipients', pending: invalid }, { status: 400 })
  // Send emails and store deliveries; record alert_recipients(start)
  if (recipients.length > 0 && !env.WEB_PUBLIC_BASE) {
    // 明示的に設定がない場合はサーバー設定不備として返却（無音スキップをやめる）
    return json({ error: 'server_misconfig', detail: 'WEB_PUBLIC_BASE is missing' }, { status: 500 })
  }
  if (recipients.length > 0 && env.WEB_PUBLIC_BASE) {
    // sender name (if available) for better trust in email content
    let senderName: string | undefined
    try {
      const m = (req.headers.get('authorization') || req.headers.get('Authorization') || '').match(/^Bearer\s+(.+)$/i)
      const token = m ? m[1] : ''
      if (token) { const supa = await fetchSupabaseUser(env, token); if (supa.ok) senderName = supa.name || (supa.email ? String(supa.email).split('@')[0] : undefined) }
    } catch {}
    const emailer = makeEmailProvider(env)
    for (const r of recipients) {
      const token = await signJwtHs256({ alert_id: alertId, contact_id: r.contact_id, scope: 'viewer', exp: nowSec() + 24 * 3600 }, env.JWT_SECRET)
      const link = `${env.WEB_PUBLIC_BASE.replace(/\/$/, '')}/s/${encodeURIComponent(token)}`
      try {
        const subj = initial.type === 'going_home'
          ? `${senderName ? senderName + 'さんが' : '送信者が'}「帰る」共有を開始しました（KokoSOS）`
          : `${senderName ? senderName + 'さんが' : '送信者が'}いまの状況を共有しています（KokoSOS）`
        const html = initial.type === 'going_home'
          ? emailInviteHtmlGoingHome(link, senderName || null)
          : emailInviteHtmlEmergency(link, senderName || null)
        const text = initial.type === 'going_home'
          ? emailInviteTextGoingHome(link, senderName || null)
          : emailInviteTextEmergency(link, senderName || null)
        await emailer.send({ to: r.email, subject: subj, html, text })
        await sb.insert('deliveries', { alert_id: alertId, contact_id: r.contact_id, channel: 'email', status: 'sent' })
        await sb.insert('alert_recipients', { alert_id: alertId, contact_id: r.contact_id, email: r.email, purpose: 'start' })
      } catch (e) {
        await sb.insert('deliveries', { alert_id: alertId, contact_id: r.contact_id, channel: 'email', status: 'error' })
      }
    }
  }
  const state = {
    type: initial.type as 'emergency' | 'going_home',
    id: alertId,
    status: 'active',
    started_at: startedAt,
    max_duration_sec: initial.max_duration_sec,
    latest: {
      lat: initial.lat,
      lng: initial.lng,
      accuracy_m: initial.accuracy_m ?? null,
      battery_pct: initial.battery_pct ?? null,
      captured_at: startedAt,
    },
    shareToken,
  }
  return json(state)
}

// ---------- Contacts API
function isValidEmail(email: string): boolean {
  return /.+@.+\..+/.test(email)
}

async function handleContactsList({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  // Always require authenticated user; fall back to Supabase /auth/v1/user if needed
  const authz = req.headers.get('authorization') || req.headers.get('Authorization')
  if (!authz) return json({ error: 'unauthorized', detail: 'missing_authorization' }, { status: 401 })
  let userId: string | null = null
  const auth = await getSenderFromAuth(req, env)
  let senderEmail: string | undefined
  let senderName: string | undefined
  if (auth.ok && auth.userId) {
    userId = auth.userId
    // 可能ならメールも取得（トークンがある場合）
    const m = authz.match(/^Bearer\s+(.+)$/i)
    const token = m ? m[1] : ''
    if (token) {
      try {
        const supa = await fetchSupabaseUser(env, token)
        if (supa.ok) { senderEmail = supa.email; senderName = supa.name }
      } catch {}
    }
  } else {
    const m = authz.match(/^Bearer\s+(.+)$/i)
    const token = m ? m[1] : ''
    const supa = await fetchSupabaseUser(env, token)
    if (!supa.ok || !supa.userId) return json({ error: 'unauthorized', detail: 'invalid_token' }, { status: 401 })
    userId = supa.userId
    senderEmail = supa.email
    senderName = supa.name
  }
  const url = new URL(req.url)
  const status = (url.searchParams.get('status') || 'all').toLowerCase()
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  let query = `user_id=eq.${encodeURIComponent(userId!)}`
  if (status === 'verified') query += `&verified_at=not.is.null`
  else if (status === 'pending') query += `&verified_at=is.null`
  const res = await sb.select('contacts', 'id,name,email,role,capabilities,verified_at', query)
  return json({ items: res.ok ? res.data : [] })
}

async function handleContactsBulkUpsert({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const authz = req.headers.get('authorization') || req.headers.get('Authorization')
  if (!authz) return json({ error: 'unauthorized', detail: 'missing_authorization' }, { status: 401 })
  let userId: string | null = null
  const auth = await getSenderFromAuth(req, env)
  // 送信者のメール/名前（件名や本文に利用）
  let senderEmail: string | undefined
  let senderName: string | undefined
  if (auth.ok && auth.userId) {
    userId = auth.userId
    // トークンからメール/名前を取得（可能なら）
    try {
      const m = authz.match(/^Bearer\s+(.+)$/i)
      const token = m ? m[1] : ''
      if (token) {
        const supa = await fetchSupabaseUser(env, token)
        if (supa.ok) { senderEmail = supa.email; senderName = supa.name }
      }
    } catch {}
  } else {
    const m = authz.match(/^Bearer\s+(.+)$/i)
    const token = m ? m[1] : ''
    const supa = await fetchSupabaseUser(env, token)
    if (!supa.ok || !supa.userId) return json({ error: 'unauthorized', detail: 'invalid_token' }, { status: 401 })
    userId = supa.userId
    senderEmail = supa.email
    senderName = supa.name
  }
  const body = await req.json().catch(() => null)
  if (!body || !Array.isArray(body.contacts)) return json({ error: 'invalid_body' }, { status: 400 })
  const sendVerify = Boolean(body.send_verify)
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  await ensureUserExists(sb, userId!)
  const out: any[] = []
  const verifyFailed: string[] = []
  for (const c of body.contacts as Array<{ email: string; name?: string }>) {
    const email = String((c.email || '').toLowerCase().trim())
    if (!isValidEmail(email)) continue
    // Try find by email
    const found = await sb.select('contacts', 'id,email,verified_at', `user_id=eq.${encodeURIComponent(userId!)}&email=eq.${encodeURIComponent(email)}`, 1)
    if (found.ok && found.data.length > 0) {
      out.push(found.data[0])
    } else {
      const ins = await sb.insert('contacts', { user_id: userId, name: c.name || email, email })
      if (ins.ok && ins.data.length > 0) out.push(ins.data[0])
    }
    if (sendVerify) {
      const list = await sb.select('contacts', 'id,email,verified_at', `user_id=eq.${encodeURIComponent(userId!)}&email=eq.${encodeURIComponent(email)}`, 1)
      if (list.ok && list.data.length > 0 && !(list.data[0] as any).verified_at) {
        try {
          // 名前が無い場合はメールのローカル部から推測
          const display = senderName && senderName.length > 0
            ? senderName
            : (senderEmail ? String(senderEmail).split('@')[0] : null)
          await sendVerifyForContact(env, list.data[0] as any, display || null, undefined)
        } catch {
          verifyFailed.push(email)
        }
      }
    }
  }
  const bodyOut: any = { ok: true, items: out }
  if (verifyFailed.length > 0) bodyOut.verify_failed = verifyFailed
  return json(bodyOut)
}

async function handleContactSendVerify({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const authz = req.headers.get('authorization') || req.headers.get('Authorization')
  if (!authz) return json({ error: 'unauthorized', detail: 'missing_authorization' }, { status: 401 })
  const auth = await getSenderFromAuth(req, env)
  if (!auth.ok || !auth.userId) return json({ error: 'unauthorized', detail: 'invalid_token' }, { status: auth.status })
  // 送信者メール（あれば）
  let senderEmail: string | undefined
  let senderName: string | undefined
  try {
    const m = authz.match(/^Bearer\s+(.+)$/i)
    const token = m ? m[1] : ''
    if (token) { const supa = await fetchSupabaseUser(env, token); if (supa.ok) { senderEmail = supa.email; senderName = supa.name } }
  } catch {}
  const m = req.url.match(/\/contacts\/([^/]+)\/send_verify/)
  if (!m) return notFound()
  const id = m[1]
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  const found = await sb.select('contacts', 'id,email,verified_at', `id=eq.${id}`, 1)
  if (!found.ok || found.data.length === 0) return json({ error: 'not_found' }, { status: 404 })
  const c = found.data[0] as any
  const display = senderName && senderName.length > 0
    ? senderName
    : (senderEmail ? String(senderEmail).split('@')[0] : null)
  await sendVerifyForContact(env, c, display || null, undefined)
  return json({ ok: true })
}

// -------- Devices register/unregister (FCM)
async function handleDevicesRegister({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const authz = req.headers.get('authorization') || req.headers.get('Authorization') || ''
  const primary = await getSenderFromAuth(req, env)
  let userId: string | null = primary.ok ? (primary as any).userId ?? null : null
  if (!userId && authz) {
    try {
      const m = authz.match(/^Bearer\s+(.+)$/i)
      const token = m ? m[1] : ''
      if (token) {
        const supa = await fetchSupabaseUser(env, token)
        if (supa.ok && supa.userId) userId = supa.userId
      }
    } catch {}
  }
  if (!userId) return json({ error: 'unauthorized' }, { status: (primary as any).status || 401 })
  const body = await req.json().catch(() => null)
  if (!body || typeof body.fcm_token !== 'string' || typeof body.platform !== 'string') return json({ error: 'invalid_body' }, { status: 400 })
  const token = String(body.fcm_token).trim()
  const platform = String(body.platform).trim().toLowerCase()
  if (!token || !/^ios|android|web$/.test(platform)) return json({ error: 'invalid_body' }, { status: 400 })
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  // Upsert: if exists, update valid/last_seen; else insert
  const found = await sb.select('devices', 'id,fcm_token,valid', `user_id=eq.${encodeURIComponent(userId)}&fcm_token=eq.${encodeURIComponent(token)}`, 1)
  if (found.ok && found.data.length > 0) {
    const id = String((found.data[0] as any).id)
    await sb.update('devices', { valid: true, last_seen_at: new Date().toISOString(), platform }, `id=eq.${encodeURIComponent(id)}`)
  } else {
    await sb.insert('devices', { user_id: userId, platform, fcm_token: token, valid: true })
  }
  // Best-effort: remove duplicate rows if any (same user_id + fcm_token)
  try {
    const dups = await sb.select(
      'devices',
      'id,created_at',
      `user_id=eq.${encodeURIComponent(userId)}&fcm_token=eq.${encodeURIComponent(token)}&order=created_at.asc`
    )
    if (dups.ok && (dups.data as any[]).length > 1) {
      const keep = String((dups.data as any[])[0].id)
      const removeIds = (dups.data as any[])
        .map((r) => String(r.id))
        .filter((x) => x !== keep)
      if (removeIds.length > 0) {
        await sb.delete('devices', `id=in.(${removeIds.map(encodeURIComponent).join(',')})`)
      }
    }
  } catch {}
  return json({ ok: true })
}

async function handleDevicesUnregister({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const authz = req.headers.get('authorization') || req.headers.get('Authorization') || ''
  const primary = await getSenderFromAuth(req, env)
  let userId: string | null = primary.ok ? (primary as any).userId ?? null : null
  if (!userId && authz) {
    try {
      const m = authz.match(/^Bearer\s+(.+)$/i)
      const token = m ? m[1] : ''
      if (token) {
        const supa = await fetchSupabaseUser(env, token)
        if (supa.ok && supa.userId) userId = supa.userId
      }
    } catch {}
  }
  if (!userId) return json({ error: 'unauthorized' }, { status: (primary as any).status || 401 })
  const body = await req.json().catch(() => null)
  if (!body || typeof body.fcm_token !== 'string') return json({ error: 'invalid_body' }, { status: 400 })
  const token = String(body.fcm_token).trim()
  if (!token) return json({ error: 'invalid_body' }, { status: 400 })
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  await sb.update('devices', { valid: false, last_seen_at: new Date().toISOString() }, `user_id=eq.${encodeURIComponent(userId)}&fcm_token=eq.${encodeURIComponent(token)}`)
  return json({ ok: true })
}

async function sendVerifyForContact(env: Env, contact: { id: string; email: string }, senderName?: string | null, senderAvatarUrl?: string | null) {
  if (!env.WEB_PUBLIC_BASE) return
  const token = await signJwtHs256({ action: 'verify', contact_id: contact.id, exp: nowSec() + 7 * 24 * 3600 }, env.JWT_SECRET)
  const link = `${env.WEB_PUBLIC_BASE.replace(/\/$/, '')}/verify/${encodeURIComponent(token)}`
  const emailer = makeEmailProvider(env)
  if (isEmailDebug(env)) {
    console.log(`[EMAIL-DEV] verify start -> ${maskEmail(String(contact.email))}`)
  }
  try {
    const subject = senderName && senderName.length > 0
      ? `${senderName}さんからKokoSOSの受信者（見守り）依頼が届いています`
      : 'KokoSOS 受信許可の確認'
    const html = emailVerifyHtml(link, senderName || null, senderAvatarUrl || null)
    const text = emailVerifyText(link, senderName || null)
    await emailer.send({ to: String(contact.email), subject, html, text })
    if (isEmailDebug(env)) {
      console.log(`[EMAIL-DEV] verify sent ok -> ${maskEmail(String(contact.email))}`)
    }
  } catch (e) {
    if (isEmailDebug(env)) {
      console.log(`[EMAIL-DEV] verify failed -> ${maskEmail(String(contact.email))} : ${String(e).slice(0,200)}`)
    }
    throw e
  }
}

async function handleVerifyContact({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const token = decodeURIComponent(req.url.split('/public/verify/')[1] || '')
  const payload = await verifyJwtHs256(token, env.JWT_SECRET)
  if (!payload) return json({ ok: false, error: 'invalid_token' }, { status: 400 })
  if ((payload as any).action !== 'verify') return json({ ok: false, error: 'invalid_action' }, { status: 400 })
  const contactId = String((payload as any).contact_id || '')
  if (!contactId) return json({ ok: false, error: 'invalid_contact' }, { status: 400 })
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  await sb.update('contacts', { verified_at: new Date().toISOString() }, `id=eq.${contactId}`)
  return json({ ok: true })
}

// ---------- Account deletion (caller = authenticated sender)
async function handleAccountDelete({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  // 強制的に本人認証を要求（REQUIRE_AUTH_SENDER に依存しない）
  const authz = req.headers.get('authorization') || req.headers.get('Authorization')
  if (!authz) return json({ error: 'unauthorized', detail: 'missing_authorization' }, { status: 401 })
  let userId: string | null = null
  // 1) まず既存のJWT検証（JWKS）を試す
  const auth = await getSenderFromAuth(req, env)
  if (auth.ok && auth.userId) {
    userId = auth.userId
  } else {
    // 2) フォールバック: Supabase Authの /auth/v1/user を呼んで検証
    try {
      const token = (authz.match(/^Bearer\s+(.+)$/i) || [])[1]
      if (!token) return json({ error: 'unauthorized', detail: 'invalid_authorization_header' }, { status: 401 })
      const u = await fetchSupabaseUser(env, token)
      if (!u.ok || !u.userId) return json({ error: 'unauthorized', detail: 'invalid_token_via_supabase' }, { status: 401 })
      userId = u.userId
    } catch {
      return json({ error: 'unauthorized', detail: 'verify_failed' }, { status: 401 })
    }
  }
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })

  // Best effort: delete app data (alerts, contacts, users) before Auth user deletion
  try {
    // Delete devices (FCM tokens) registered for this user
    await sb.delete('devices', `user_id=eq.${encodeURIComponent(userId)}`)
    // Delete alerts (will cascade locations, deliveries(alert), alert_recipients, reactions(alert), revocations)
    await sb.delete('alerts', `user_id=eq.${encodeURIComponent(userId)}`)
    // Delete contacts (deliveries(contact) will cascade if FK, reactions(alert) already gone)
    await sb.delete('contacts', `user_id=eq.${encodeURIComponent(userId)}`)
    // Delete app-side users row (in case CASCADE is not configured from auth.users)
    await sb.delete('users', `id=eq.${encodeURIComponent(userId)}`)
  } catch {}

  // Best effort: delete avatar in Storage (if present in user_metadata)
  try {
    const token = (authz.match(/^Bearer\s+(.+)$/i) || [])[1]
    if (token && env.SUPABASE_URL && env.SUPABASE_SERVICE_ROLE_KEY) {
      const u = await fetchSupabaseUser(env, token)
      const avatar = u.ok ? (u.avatarUrl || '') : ''
      // Expect format like 'avatars/{path}' or '{bucket}/{path}'
      if (avatar && /^(avatars)\//.test(avatar)) {
        const [, bucketAndPath] = avatar.match(/^([^/]+)\/(.+)$/) || []
        if (bucketAndPath) {
          const parts = avatar.split('/')
          const bucket = parts.shift() as string
          const objPath = parts.join('/')
          const delUrl = `${env.SUPABASE_URL.replace(/\/$/, '')}/storage/v1/object/${encodeURIComponent(bucket)}/${encodeURIComponent(objPath)}`
          await fetch(delUrl, {
            method: 'DELETE',
            headers: {
              apikey: env.SUPABASE_SERVICE_ROLE_KEY,
              Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
            },
          }).catch(() => undefined)
        }
      }
    }
  } catch {}

  // Delete Supabase Auth user via Admin API
  try {
    const adminUrl = `${env.SUPABASE_URL!.replace(/\/$/, '')}/auth/v1/admin/users/${encodeURIComponent(userId)}`
    const headers = {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY as string,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
    }
    const res = await fetch(adminUrl, { method: 'DELETE', headers })
    if (!res.ok && res.status !== 404) {
      const t = await res.text()
      return json({ ok: false, error: 'auth_delete_failed', detail: `${res.status} ${t}` }, { status: 500 })
    }
  } catch (e) {
    return json({ ok: false, error: 'auth_delete_failed' }, { status: 500 })
  }

  return json({ ok: true })
}

async function fetchSupabaseUser(env: Env, accessToken: string): Promise<{ ok: boolean; userId?: string; email?: string; name?: string; avatarUrl?: string }> {
  const base = env.SUPABASE_URL?.replace(/\/$/, '')
  if (!base) return { ok: false }
  const url = `${base}/auth/v1/user`
  const res = await fetch(url, {
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY as string, // or anon key if preferred
      Authorization: `Bearer ${accessToken}`,
    },
  })
  if (!res.ok) return { ok: false }
  const j = (await res.json()) as { id?: string; email?: string; user_metadata?: Record<string, unknown> }
  const md = (j.user_metadata || {}) as Record<string, unknown>
  const name =
    (typeof md['full_name'] === 'string' && md['full_name'] as string) ||
    (typeof md['name'] === 'string' && md['name'] as string) ||
    (typeof md['user_name'] === 'string' && md['user_name'] as string) ||
    (typeof md['nickname'] === 'string' && md['nickname'] as string) || undefined
  const avatarUrl =
    (typeof md['avatar_url'] === 'string' && md['avatar_url'] as string) ||
    (typeof md['picture'] === 'string' && md['picture'] as string) || undefined
  return { ok: true, userId: j.id || undefined, email: j.email || undefined, name, avatarUrl }
}

async function handleAlertUpdate({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const user = await getSenderFromAuth(req, env)
  if (!user.ok) return json({ error: user.error }, { status: user.status })
  const body = await req.json().catch(() => null)
  if (!body) return json({ error: 'invalid_json' }, { status: 400 })
  const m = req.url.match(/\/alert\/([^/]+)\/update/)
  if (!m) return notFound()
  const alertId = m[1]
  const { lat, lng, accuracy_m, battery_pct } = body as { lat: number; lng: number; accuracy_m?: number; battery_pct?: number }
  if (typeof lat !== 'number' || typeof lng !== 'number') return json({ error: 'invalid_location' }, { status: 400 })
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  // If this alert is "going_home", do not store or broadcast live locations (privacy-friendly mode)
  const typeRes = await sb.select('alerts', 'type', `id=eq.${alertId}`, 1)
  if (!typeRes.ok) return json({ error: 'db_error', detail: typeRes.error }, { status: 500 })
  const aType = typeRes.data[0]?.type as string | undefined
  if (aType === 'going_home') {
    return json({ ok: true, ignored: true })
  }
  const captured_at = new Date().toISOString()
  await sb.insert('locations', { alert_id: alertId, lat, lng, accuracy_m: accuracy_m ?? null, battery_pct: battery_pct ?? null, captured_at })
  const stub = env.ALERT_HUB.get(env.ALERT_HUB.idFromName(alertId))
  await stub.fetch('https://do/publish', { method: 'POST', body: JSON.stringify({ type: 'location', latest: { lat, lng, accuracy_m: accuracy_m ?? null, battery_pct: battery_pct ?? null, captured_at } }) })
  return json({ ok: true })
}

async function handleAlertStop({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const user = await getSenderFromAuth(req, env)
  if (!user.ok) return json({ error: user.error }, { status: user.status })
  const m = req.url.match(/\/alert\/([^/]+)\/stop/)
  if (!m) return notFound()
  const alertId = m[1]
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  const ended_at = new Date().toISOString()
  await sb.update('alerts', { status: 'ended', ended_at }, `id=eq.${alertId}`)
  // Check alert type to decide push behavior on stop
  let alertType: 'emergency' | 'going_home' | null = null
  try {
    const t = await sb.select('alerts', 'type', `id=eq.${alertId}`, 1)
    if (t.ok && t.data.length > 0) {
      const v = String((t.data[0] as any).type)
      if (v === 'emergency' || v === 'going_home') alertType = v as any
    }
  } catch {}
  const stub = env.ALERT_HUB.get(env.ALERT_HUB.idFromName(alertId))
  await stub.fetch('https://do/publish', { method: 'POST', body: JSON.stringify({ type: 'status', status: 'ended' }) })
  // Push on stop is disabled for both modes (emergency/going_home)
  // Send stop/arrival emails to recipients (both modes)
  try {
    const aType = alertType || ''
    if (env.WEB_PUBLIC_BASE) {
      const list = await sb.select('alert_recipients', 'contact_id,email', `alert_id=eq.${alertId}&purpose=eq.start`)
      const emailer = makeEmailProvider(env)
      for (const r of (list.ok ? (list.data as any[]) : [])) {
        try {
          // going_home は『到着』メール、emergency も現状は同文面（共有停止）で通知
          await emailer.send({ to: String(r.email), subject: aType === 'going_home' ? 'KokoSOS 到着のお知らせ' : 'KokoSOS 共有停止のお知らせ', html: emailArrivalHtml(), text: emailArrivalText() })
          await sb.insert('alert_recipients', { alert_id: alertId, contact_id: String(r.contact_id), email: String(r.email), purpose: aType === 'going_home' ? 'arrival' : 'stop' })
          await sb.insert('deliveries', { alert_id: alertId, contact_id: String(r.contact_id), channel: 'email', status: 'sent' })
        } catch {}
      }
    }
  } catch {}
  return json({ status: 'ended' })
}

async function handleAlertExtend({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const user = await getSenderFromAuth(req, env)
  if (!user.ok) return json({ error: user.error }, { status: user.status })
  const m = req.url.match(/\/alert\/([^/]+)\/extend/)
  if (!m) return notFound()
  const alertId = m[1]
  const body = await req.json().catch(() => null)
  if (!body) return json({ error: 'invalid_json' }, { status: 400 })
  const extend_sec_raw = (body.extend_sec as number | undefined) ?? ((body.extend_min as number | undefined) ? (body.extend_min as number) * 60 : undefined)
  if (typeof extend_sec_raw !== 'number' || !Number.isFinite(extend_sec_raw)) return json({ error: 'invalid_body' }, { status: 400 })
  const extendSec = Math.max(60, Math.min(6 * 3600, Math.floor(extend_sec_raw)))
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  const a = await sb.select('alerts', 'id,status,max_duration_sec,started_at,ended_at', `id=eq.${alertId}`, 1)
  if (!a.ok || a.data.length === 0) return json({ error: 'not_found' }, { status: 404 })
  const alert = a.data[0] as any
  if (alert.status !== 'active') return json({ error: 'not_active' }, { status: 400 })
  const current = Number(alert.max_duration_sec) || 3600
  const nextMax = Math.min(6 * 3600, current + extendSec)
  await sb.update('alerts', { max_duration_sec: nextMax }, `id=eq.${alertId}`)
  // Optional: nudge receivers
  try {
    const stub = env.ALERT_HUB.get(env.ALERT_HUB.idFromName(alertId))
    const remaining = computeRemaining(alert.started_at as string, nextMax, alert.ended_at as string | null)
    const added = nextMax - current
    await stub.fetch('https://do/publish', {
      method: 'POST',
      body: JSON.stringify({ type: 'extended', max_duration_sec: nextMax, remaining_sec: remaining, added_sec: added }),
    })
  } catch {}
  return json({ ok: true, max_duration_sec: nextMax })
}

async function handleAlertRevoke({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const user = await getSenderFromAuth(req, env)
  if (!user.ok) return json({ error: user.error }, { status: user.status })
  const m = req.url.match(/\/alert\/([^/]+)\/revoke/)
  if (!m) return notFound()
  const alertId = m[1]
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  const revoked_at = new Date().toISOString()
  await sb.insert('revocations', { alert_id: alertId, revoked_at }).catch(async () => {
    // if exists, ignore
  })
  await sb.update('alerts', { revoked_at, status: 'ended' }, `id=eq.${alertId}`)
  const stub = env.ALERT_HUB.get(env.ALERT_HUB.idFromName(alertId))
  await stub.fetch('https://do/publish', { method: 'POST', body: JSON.stringify({ type: 'status', status: 'ended' }) })
  return json({ revoked: true })
}

async function handlePublicAlert({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const token = decodeURIComponent(req.url.split('/public/alert/')[1] || '')
  const payload = await withJwtFromPathToken(req, env, token)
  if (!payload) return json({ error: 'invalid_token' }, { status: 401 })
  const alertId = String((payload as any).alert_id)
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  // Revocation check
  const revoked = await sb.select('revocations', '*', `alert_id=eq.${alertId}`, 1)
  if (revoked.ok && revoked.data.length > 0) return json({ error: 'revoked' }, { status: 401 })
  const alertRes = await sb.select('alerts', '*', `id=eq.${alertId}`, 1)
  if (!alertRes.ok || alertRes.data.length === 0) return json({ error: 'not_found' }, { status: 404 })
  const alert = alertRes.data[0]
  // In "going_home" mode, do not expose latest location to public API
  let latest: any = null
  if (alert.type !== 'going_home') {
    const latestRes = await sb.select('locations', '*', `alert_id=eq.${alertId}&order=captured_at.desc&limit=1`, 1)
    latest = latestRes.ok && latestRes.data.length > 0 ? latestRes.data[0] : null
  }
  const remaining = computeRemaining(alert.started_at, alert.max_duration_sec, alert.ended_at)
  const resp = {
    type: (alert.type as 'emergency' | 'going_home') ?? 'emergency',
    status: (alert.status as 'active' | 'ended' | 'timeout') ?? 'active',
    remaining_sec: remaining,
    latest: latest
      ? { lat: latest.lat, lng: latest.lng, accuracy_m: latest.accuracy_m ?? null, battery_pct: latest.battery_pct ?? null, captured_at: latest.captured_at }
      : null,
    permissions: { 
      can_call: true, 
      can_reply: !!(payload as any).contact_id, 
      can_call_police: true 
    },
  }
  return json(resp)
}

async function handlePublicAlertStream({ req, env, ctx }: Parameters<RouteHandler>[0]): Promise<Response> {
  const token = decodeURIComponent(req.url.split('/public/alert/')[1]?.replace(/\/stream$/, '') || '')
  const payload = await withJwtFromPathToken(req, env, token)
  if (!payload) return json({ error: 'invalid_token' }, { status: 401 })
  const alertId = String((payload as any).alert_id)
  // Bridge Durable Object (WebSocket) -> SSE
  const stub = env.ALERT_HUB.get(env.ALERT_HUB.idFromName(alertId))
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const enc = new TextEncoder()
      controller.enqueue(enc.encode(`retry: 10000\n\n`))
      // Establish DO websocket (per latest Durable Objects API)
      console.log('stream_ws_connect_start', { alertId })
      let client: WebSocket
      try {
        const res = await stub.fetch('https://do/ws', { headers: { Upgrade: 'websocket' } })
        // Response to an Upgrade request contains a webSocket in Workers runtime
        const ws = (res as unknown as { webSocket?: WebSocket }).webSocket
        if (!ws) throw new Error('no_websocket_returned')
        client = ws
      } catch (e) {
        console.log('stream_ws_connect_failed', { alertId, error: (e as Error)?.message })
        controller.enqueue(enc.encode(`data: ${JSON.stringify({ type: 'error', message: 'do_connect_failed' })}\n\n`))
        controller.close()
        return
      }
      client.accept()
      console.log('stream_ws_connect_ok', { alertId })
      // Send hello immediately so intermediaries keep the stream open
      controller.enqueue(enc.encode(`data: ${JSON.stringify({ type: 'hello', ts: Date.now() })}\n\n`))
      // Periodic keepalive independent of DO messages
      const ka = setInterval(() => {
        try { controller.enqueue(enc.encode(`data: ${JSON.stringify({ type: 'keepalive', ts: Date.now() })}\n\n`)) } catch {}
      }, 25000)
      client.addEventListener('message', (ev: MessageEvent) => {
        controller.enqueue(enc.encode(`data: ${String(ev.data)}\n\n`))
      })
      const onClose = () => {
        clearInterval(ka)
        controller.close()
      }
      client.addEventListener('close', onClose)
      client.addEventListener('error', onClose)
    },
    cancel() {
      try { client.close() } catch {}
    },
  })
  const headers: HeadersInit = {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache, no-transform',
    connection: 'keep-alive',
    ...securityHeaders(),
  }
  return new Response(stream, { headers })
}

async function handlePublicAlertLocations({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const url = new URL(req.url)
  const token = decodeURIComponent(url.pathname.split('/public/alert/')[1]?.replace(/\/locations$/, '') || '')
  const payload = await withJwtFromPathToken(req, env, token)
  if (!payload) return json({ error: 'invalid_token' }, { status: 401 })
  const alertId = String((payload as any).alert_id)
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  // Revocation check
  const revoked = await sb.select('revocations', '*', `alert_id=eq.${alertId}`, 1)
  if (revoked.ok && revoked.data.length > 0) return json({ error: 'revoked' }, { status: 401 })
  // In "going_home" mode, do not return location history
  const alertRes = await sb.select('alerts', 'type', `id=eq.${alertId}`, 1)
  if (!alertRes.ok) return json({ error: 'db_error', detail: alertRes.error }, { status: 500 })
  const aType = alertRes.data[0]?.type as string | undefined
  if (aType === 'going_home') return json({ items: [] })
  const limit = clampInt(url.searchParams.get('limit'), 1, 500, 100)
  const order = (url.searchParams.get('order') || 'asc').toLowerCase() === 'desc' ? 'desc' : 'asc'
  const q = `alert_id=eq.${alertId}&order=captured_at.${order}&limit=${limit}`
  const res = await sb.select('locations', 'lat,lng,accuracy_m,battery_pct,captured_at', q)
  if (!res.ok) return json({ error: 'db_error', detail: res.error }, { status: 500 })
  return json({ items: res.data })
}

async function handlePublicAlertReact({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const token = decodeURIComponent(req.url.split('/public/alert/')[1]?.replace(/\/react$/, '') || '')
  const payload = await withJwtFromPathToken(req, env, token)
  if (!payload) return json({ error: 'invalid_token' }, { status: 401 })
  const body = await req.json().catch(() => null)
  if (!body || typeof body.preset !== 'string') return json({ error: 'invalid_body' }, { status: 400 })
  const preset: string = String(body.preset)
  // only allow simple short tokens like 'ok', 'help', 'call_police'
  if (!/^[a-z0-9_-]{1,32}$/i.test(preset)) return json({ error: 'invalid_preset' }, { status: 400 })
  const alertId = String((payload as any).alert_id)
  const contactId = (payload as any).contact_id as string | undefined
  if (!contactId) return json({ error: 'forbidden' }, { status: 403 })
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  // Duplicate suppression window: if same preset from same contact within 5s, skip push (and skip DB insert)
  let isDuplicateRecent = false
  try {
    const last = await sb.select(
      'reactions',
      'id,created_at,preset,contact_id',
      `alert_id=eq.${encodeURIComponent(alertId)}&contact_id=eq.${encodeURIComponent(contactId)}&preset=eq.${encodeURIComponent(preset)}&order=created_at.desc&limit=1`,
      1
    )
    if (last.ok && last.data.length > 0) {
      const ts = new Date(String((last.data[0] as any).created_at)).getTime()
      if (Date.now() - ts < 5000) isDuplicateRecent = true
    }
  } catch {}
  if (!isDuplicateRecent) {
    // Save only when not recent duplicate
    await sb.insert('reactions', { alert_id: alertId, contact_id: contactId, preset })
  }
  // Broadcast
  try {
    const stub = env.ALERT_HUB.get(env.ALERT_HUB.idFromName(alertId))
    await stub.fetch('https://do/publish', { method: 'POST', body: JSON.stringify({ type: 'reaction', preset, ts: Date.now() }) })
  } catch {}
  // Push notify sender devices (best-effort)
  let push: 'sent' | 'skipped' | 'error' = 'skipped'
  try {
    if (env.FCM_PROJECT_ID && env.FCM_CLIENT_EMAIL && env.FCM_PRIVATE_KEY) {
      if (!isDuplicateRecent) {
        await pushNotifySenderForReaction(env, alertId, preset, contactId)
        push = 'sent'
      } else {
        push = 'skipped'
      }
    } else {
      push = 'skipped'
    }
  } catch {
    push = 'error'
  }
  return json({ ok: true, push })
}

async function signJwtHs256(payload: Record<string, unknown>, secret: string): Promise<string> {
  const header = { alg: 'HS256', typ: 'JWT' }
  const enc = new TextEncoder()
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const h = base64url(JSON.stringify(header))
  const p = base64url(JSON.stringify(payload))
  const data = `${h}.${p}`
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(data))
  const s = base64urlArr(new Uint8Array(sig))
  return `${data}.${s}`
}

function base64url(input: string): string {
  let s = btoa(unescape(encodeURIComponent(input)))
  s = s.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  return s
}

function base64urlArr(input: Uint8Array): string {
  let s = ''
  for (let i = 0; i < input.length; i++) s += String.fromCharCode(input[i])
  s = btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  return s
}

// -------- FCM (HTTP v1) push utilities
type PushMessage = { title: string; body: string; category?: string; data?: Record<string, string> }

let fcmCachedToken: { token: string; exp: number } | null = null

async function getFcmAccessToken(env: Env): Promise<string> {
  if (!env.FCM_PROJECT_ID || !env.FCM_CLIENT_EMAIL || !env.FCM_PRIVATE_KEY) throw new Error('fcm_env_missing')
  const now = Math.floor(Date.now() / 1000)
  if (fcmCachedToken && fcmCachedToken.exp - 60 > now) return fcmCachedToken.token
  const header = { alg: 'RS256', typ: 'JWT' }
  const iat = now
  const exp = now + 3600
  const iss = env.FCM_CLIENT_EMAIL
  const scope = 'https://www.googleapis.com/auth/firebase.messaging'
  const aud = 'https://oauth2.googleapis.com/token'
  const payload = { iss, scope, aud, iat, exp }
  const enc = new TextEncoder()
  const toB64 = (obj: any) => base64urlArr(new Uint8Array(enc.encode(JSON.stringify(obj))))
  const h = toB64(header)
  const p = toB64(payload)
  const data = `${h}.${p}`
  // Private key may contain literal \n sequences
  const pk = (env.FCM_PRIVATE_KEY as string).replace(/\\n/g, '\n')
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8(pk),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(data))
  const assertion = `${data}.${base64urlArr(new Uint8Array(sig))}`
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${encodeURIComponent(assertion)}`,
  })
  if (!res.ok) throw new Error(`fcm_token_failed:${res.status}`)
  const j = (await res.json()) as { access_token: string; expires_in: number }
  fcmCachedToken = { token: j.access_token, exp: now + Math.max(60, Math.min(3600, Number(j.expires_in || 3600))) }
  return fcmCachedToken.token
}

// -------- Auth email: generate_link + send
type AuthEmailKind = 'confirm_signup' | 'invite' | 'magic_link' | 'change_email_current' | 'change_email_new' | 'reset_password' | 'reauth'

async function handleAuthEmailSend({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  try {
    if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) return json({ error: 'server_misconfig' }, { status: 500 })
    const authz = req.headers.get('authorization') || req.headers.get('Authorization') || ''
    const okAdmin = authz === `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`
    if (!okAdmin) return json({ error: 'unauthorized' }, { status: 401 })
    const body = await req.json().catch(() => null) as any
    if (!body || typeof body.kind !== 'string' || typeof body.email !== 'string') return json({ error: 'invalid_body' }, { status: 400 })
    const kind = body.kind as AuthEmailKind
    const email = String(body.email).trim()
    const redirect_to = sanitizeRedirect(env, typeof body.redirect_to === 'string' ? String(body.redirect_to) : undefined)
    const new_email = typeof body.new_email === 'string' ? String(body.new_email).trim() : undefined
    const mapping: Record<AuthEmailKind, string> = {
      confirm_signup: 'signup',
      invite: 'invite',
      magic_link: 'magiclink',
      change_email_current: 'email_change_current',
      change_email_new: 'email_change_new',
      reset_password: 'recovery',
      reauth: 'magiclink',
    }
    const type = mapping[kind]
    const payload: any = { type, email }
    if (redirect_to) payload.redirect_to = redirect_to
    if (kind === 'change_email_new') payload.new_email = new_email
    // Call Supabase Admin generate_link
    const { ok, link, detail } = await supabaseGenerateLink(env, payload)
    if (!ok || !link) return json({ error: 'generate_link_failed', detail }, { status: 500 })
    const action_link: string = link
    if (!action_link) return json({ error: 'no_action_link' }, { status: 500 })
    // Build email content
    const { subject, html, text } = buildAuthEmail(kind, action_link, email, new_email, env.WEB_PUBLIC_BASE || undefined)
    const emailer = makeEmailProvider(env)
    const to = (kind === 'change_email_new' && new_email) ? new_email : email
    await emailer.send({ to, subject, html, text })
    return json({ ok: true })
  } catch (e) {
    return json({ error: 'unexpected', detail: String(e) }, { status: 500 })
  }
}

// Public handler: send password reset email via Supabase Admin generate_link and SES
// Security notes:
// - No Authorization required (user may be signed out when requesting reset)
// - Always return { ok: true } to avoid user enumeration
// - Server logs keep details; consider adding rate limiting in front (e.g., Cloudflare Rules)
async function handleAuthEmailResetPublic({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  try {
    if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) return json({ ok: true })
    const body = await req.json().catch(() => null) as any
    const email = typeof body?.email === 'string' ? String(body.email).trim() : ''
    if (!email) return json({ ok: true })
    const redirect_to = sanitizeRedirect(env, typeof body?.redirect_to === 'string' ? String(body.redirect_to) : undefined)
    const ip = (req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for') || '').split(',')[0].trim()
    const tsToken = String(body?.turnstile_token || body?.['cf-turnstile-response'] || '')
    if (!(await verifyTurnstile(env, tsToken, ip))) return json({ ok: true })
    // Basic rate limits: IP 5/min, Email 5/hour
    const okIp = await rateLimitCheck(env, `reset:ip:${ip || 'unknown'}`, 5, 60)
    const okEmail = await rateLimitCheck(env, `reset:email:${email.toLowerCase()}`, 5, 3600)
    if (!okIp || !okEmail) {
      if (isEmailDebug(env)) console.log('[AUTH-RESET] rate_limited:', { okIp, okEmail })
      return json({ ok: true })
    }
    const payload: any = { type: 'recovery', email }
    if (redirect_to) payload.redirect_to = redirect_to
    // Call Supabase Admin generate_link
    const { ok, link, detail } = await supabaseGenerateLink(env, payload)
    if (!ok || !link) {
      if (isEmailDebug(env)) console.log('[AUTH-RESET] generate_link failed:', detail)
      return json({ ok: true })
    }
    const action_link: string = link
    const { subject, html, text } = buildAuthEmail('reset_password', action_link, email, undefined, env.WEB_PUBLIC_BASE || undefined)
    try {
      const emailer = makeEmailProvider(env)
      await emailer.send({ to: email, subject, html, text })
      if (isEmailDebug(env)) console.log('[AUTH-RESET] sent ok ->', maskEmail(email))
    } catch (e) {
      if (isEmailDebug(env)) console.log('[EMAIL][auth.reset] failed:', String(e).slice(0,200))
    }
    return json({ ok: true })
  } catch {
    return json({ ok: true })
  }
}

// Public magic link sender
async function handleAuthEmailMagicPublic({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  try {
    if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) return json({ ok: true })
    const body = await req.json().catch(() => null) as any
    const email = typeof body?.email === 'string' ? String(body.email).trim() : ''
    if (!email) return json({ ok: true })
    const redirect_to = sanitizeRedirect(env, typeof body?.redirect_to === 'string' ? String(body.redirect_to) : undefined)
    const ip = (req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for') || '').split(',')[0].trim()
    const tsToken = String(body?.turnstile_token || body?.['cf-turnstile-response'] || '')
    if (!(await verifyTurnstile(env, tsToken, ip))) return json({ ok: true })
    // Rate limit
    const okIp = await rateLimitCheck(env, `magic:ip:${ip || 'unknown'}`, 5, 60)
    const okEmail = await rateLimitCheck(env, `magic:email:${email.toLowerCase()}`, 5, 3600)
    if (!okIp || !okEmail) { if (isEmailDebug(env)) console.log('[AUTH-MAGIC] rate_limited:', { okIp, okEmail }); return json({ ok: true }) }
    const payload: any = { type: 'magiclink', email }
    if (redirect_to) payload.redirect_to = redirect_to
    const { ok, link, detail } = await supabaseGenerateLink(env, payload)
    if (!ok || !link) { if (isEmailDebug(env)) console.log('[AUTH-MAGIC] generate_link failed:', detail); return json({ ok: true }) }
    const action_link: string = link
    const { subject, html, text } = buildAuthEmail('magic_link', action_link, email, undefined, env.WEB_PUBLIC_BASE || undefined)
    try { await makeEmailProvider(env).send({ to: email, subject, html, text }); if (isEmailDebug(env)) console.log('[AUTH-MAGIC] sent ok ->', maskEmail(email)) } catch (e) { if (isEmailDebug(env)) console.log('[EMAIL][auth.magic] failed:', String(e).slice(0,200)) }
    return json({ ok: true })
  } catch { return json({ ok: true }) }
}

// Signed-in user: send reauth magic link
async function handleAuthEmailReauth({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const user = await getSenderFromAuth(req, env)
  if (!user.ok || !(user as any).userId) return json({ error: 'unauthorized' }, { status: 401 })
  try {
    const token = (req.headers.get('authorization') || req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '')
    const supa = await fetchSupabaseUser(env, token)
    const email = supa.email || ''
    if (!email) return json({ ok: true })
    const body = await req.json().catch(() => null) as any
    const redirect_to = sanitizeRedirect(env, typeof body?.redirect_to === 'string' ? String(body.redirect_to) : undefined, 'reauth')
    const payload: any = { type: 'magiclink', email }
    if (redirect_to) payload.redirect_to = redirect_to
    const { ok, link, detail } = await supabaseGenerateLink(env, payload)
    if (!ok || !link) { if (isEmailDebug(env)) console.log('[AUTH-REAUTH] generate_link failed:', detail); return json({ ok: true }) }
    const action_link: string = link
    const { subject, html, text } = buildAuthEmail('reauth', action_link, email, undefined, env.WEB_PUBLIC_BASE || undefined)
    try { await makeEmailProvider(env).send({ to: email, subject, html, text }); if (isEmailDebug(env)) console.log('[AUTH-REAUTH] sent ok ->', maskEmail(email)) } catch (e) { if (isEmailDebug(env)) console.log('[EMAIL][auth.reauth] failed:', String(e).slice(0,200)) }
    return json({ ok: true })
  } catch { return json({ ok: true }) }
}

// Signed-in user: change email (send to current and new)
async function handleAuthEmailChangeEmail({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const user = await getSenderFromAuth(req, env)
  if (!user.ok || !(user as any).userId) return json({ error: 'unauthorized' }, { status: 401 })
  try {
    const token = (req.headers.get('authorization') || req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '')
    const supa = await fetchSupabaseUser(env, token)
    const currentEmail = supa.email || ''
    const body = await req.json().catch(() => null) as any
    const newEmail = typeof body?.new_email === 'string' ? String(body.new_email).trim() : ''
    if (!currentEmail || !newEmail) return json({ ok: true })
    const redirect_to = sanitizeRedirect(env, typeof body?.redirect_to === 'string' ? String(body.redirect_to) : undefined)
    // 1) Current email confirmation
    {
      const payload: any = { type: 'email_change_current', email: currentEmail }
      if (redirect_to) payload.redirect_to = redirect_to
      const g1 = await supabaseGenerateLink(env, payload)
      if (g1.ok && g1.link) {
        const link1 = g1.link
        const mail = buildAuthEmail('change_email_current', link1, currentEmail, newEmail, env.WEB_PUBLIC_BASE || undefined)
        try { await makeEmailProvider(env).send({ to: currentEmail, subject: mail.subject, html: mail.html, text: mail.text }); if (isEmailDebug(env)) console.log('[AUTH-EMAIL-CHANGE current] sent ok ->', maskEmail(currentEmail)) } catch (e) { if (isEmailDebug(env)) console.log('[EMAIL][auth.email_change_current] failed:', String(e).slice(0,200)) }
      }
    }
    // 2) New email confirmation
    {
      const payload: any = { type: 'email_change_new', email: currentEmail, new_email: newEmail }
      if (redirect_to) payload.redirect_to = redirect_to
      const g2 = await supabaseGenerateLink(env, payload)
      if (g2.ok && g2.link) {
        const link2 = g2.link
        const mail = buildAuthEmail('change_email_new', link2, currentEmail, newEmail, env.WEB_PUBLIC_BASE || undefined)
        try { await makeEmailProvider(env).send({ to: newEmail || currentEmail, subject: mail.subject, html: mail.html, text: mail.text }); if (isEmailDebug(env)) console.log('[AUTH-EMAIL-CHANGE new] sent ok ->', maskEmail(newEmail || currentEmail)) } catch (e) { if (isEmailDebug(env)) console.log('[EMAIL][auth.email_change_new] failed:', String(e).slice(0,200)) }
      }
    }
    return json({ ok: true })
  } catch { return json({ ok: true }) }
}

// Public: email/password signup via confirmation link only (no pre-creation)
async function handleAuthSignupPublic({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  try {
    const body = await req.json().catch(() => null) as any
    const email = typeof body?.email === 'string' ? String(body.email).trim() : ''
    const password = typeof body?.password === 'string' ? String(body.password) : ''
    if (!email || !password) return json({ ok: true })
    if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) return json({ ok: true })
    const redirect_to = sanitizeRedirect(env, typeof body?.redirect_to === 'string' ? String(body.redirect_to) : undefined)
    const ip = (req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for') || '').split(',')[0].trim()
    const tsToken = String(body?.turnstile_token || body?.['cf-turnstile-response'] || '')
    if (!(await verifyTurnstile(env, tsToken, ip))) return json({ ok: true })
    // Rate limit (more strict for signup)
    const okIp = await rateLimitCheck(env, `signup:ip:${ip || 'unknown'}`, 3, 300)
    const okEmail = await rateLimitCheck(env, `signup:email:${email.toLowerCase()}`, 3, 3600)
    if (!okIp || !okEmail) { if (isEmailDebug(env)) console.log('[AUTH-SIGNUP] rate_limited:', { okIp, okEmail }); return json({ ok: true }) }
    // Send confirmation link only (do not pre-create user)
    // Note: Supabase Admin generate_link('signup') requires password when creating signup link
    const payload: any = { type: 'signup', email, password }
    if (redirect_to) payload.redirect_to = redirect_to
    const g = await supabaseGenerateLink(env, payload)
    if (g.ok && g.link) {
      const mail = buildAuthEmail('confirm_signup', g.link, email, undefined, env.WEB_PUBLIC_BASE || undefined)
      try { await makeEmailProvider(env).send({ to: email, subject: mail.subject, html: mail.html, text: mail.text }); if (isEmailDebug(env)) console.log('[AUTH-SIGNUP] sent ok ->', maskEmail(email)) } catch (e) { if (isEmailDebug(env)) console.log('[EMAIL][auth.signup] failed:', String(e).slice(0,200)) }
    } else {
      if (isEmailDebug(env)) console.log('[AUTH-SIGNUP] generate_link failed:', g.detail || 'unknown')
    }
    return json({ ok: true })
  } catch {
    return json({ ok: true })
  }
}

// Dev/ops: Delete unconfirmed user by email (admin-only, to clean up accidental pre-creation)
// Authorization: Bearer <SERVICE_ROLE_KEY>
async function handleAuthDiagCleanupUnconfirmed({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  try {
    if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) return json({ error: 'server_misconfig' }, { status: 500 })
    const authz = req.headers.get('authorization') || req.headers.get('Authorization') || ''
    if (authz !== `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`) return json({ error: 'unauthorized' }, { status: 401 })
    const body = await req.json().catch(() => null) as any
    const email = typeof body?.email === 'string' ? String(body.email).trim() : ''
    if (!email) return json({ error: 'invalid_email' }, { status: 400 })
    const base = env.SUPABASE_URL.replace(/\/$/, '')
    // Lookup user by email
    const list = await fetch(`${base}/auth/v1/admin/users?email=${encodeURIComponent(email)}`, {
      method: 'GET',
      headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` },
    })
    if (!list.ok) return json({ ok: false, error: 'lookup_failed', detail: await list.text() }, { status: 500 })
    const users = await list.json().catch(() => []) as any[]
    if (!Array.isArray(users) || users.length === 0) return json({ ok: true, removed: 0 })
    let removed = 0
    for (const u of users) {
      const confirmed = Boolean(u.email_confirmed_at)
      if (!confirmed && u.id) {
        const del = await fetch(`${base}/auth/v1/admin/users/${encodeURIComponent(String(u.id))}`, {
          method: 'DELETE', headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` },
        })
        if (del.ok) removed++
      }
    }
    return json({ ok: true, removed })
  } catch (e) {
    return json({ ok: false, error: 'unexpected', detail: String(e) }, { status: 500 })
  }
}

// Helper: call Supabase Admin generate_link with redirect fallback
async function supabaseGenerateLink(env: Env, payloadIn: any): Promise<{ ok: boolean; link?: string; detail?: string }> {
  const adminURL = `${env.SUPABASE_URL!.replace(/\/$/, '')}/auth/v1/admin/generate_link`
  const headers = { apikey: env.SUPABASE_SERVICE_ROLE_KEY!, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY!}`, 'content-type': 'application/json' }
  // Try with provided redirect_to first
  let payload = { ...payloadIn }
  let res = await fetch(adminURL, { method: 'POST', headers, body: JSON.stringify(payload) })
  let text = ''
  if (!res.ok) {
    text = await res.text().catch(() => '')
    const isRedirectError = /redirect|allow(ed)?\s*url|not\s*in\s*(the\s*)?list/i.test(text)
    if (isRedirectError && 'redirect_to' in payload) {
      // Retry via web callback to preserve tokens and forward to app
      try {
        const original = String((payload as any).redirect_to || '')
        if (env.WEB_PUBLIC_BASE) {
          const webCb = `${String(env.WEB_PUBLIC_BASE).replace(/\/$/, '')}/auth/confirm?type=${encodeURIComponent(String((payload as any).type || ''))}&next=${encodeURIComponent(original)}`
          ;(payload as any).redirect_to = webCb
          res = await fetch(adminURL, { method: 'POST', headers, body: JSON.stringify(payload) })
        }
      } catch {}
      if (!res.ok) {
        // Final fallback: try without redirect_to (Supabase Site URL)
        try { delete (payload as any).redirect_to } catch {}
        res = await fetch(adminURL, { method: 'POST', headers, body: JSON.stringify(payload) })
        if (!res.ok) {
          const t2 = await res.text().catch(() => '')
          return { ok: false, detail: t2 || text }
        }
      }
    } else if (!res.ok) {
      return { ok: false, detail: text }
    }
  }
  const j = await res.json().catch(() => null) as any
  const link = j?.action_link || j?.properties?.action_link || j?.properties?.email_otp_link || ''
  if (!link) return { ok: false, detail: 'no_action_link' }
  return { ok: true, link }
}

// Sanitize redirect_to to prevent open redirect and scheme abuse
function sanitizeRedirect(env: Env, provided?: string, flow?: 'reauth'): string | undefined {
  const webBase = env.WEB_PUBLIC_BASE ? String(env.WEB_PUBLIC_BASE) : null
  const defaultWeb = webBase ? `${webBase.replace(/\/$/, '')}/auth/callback${flow === 'reauth' ? '?flow=reauth' : ''}` : undefined
  // Allow custom app schemes configured via APP_SCHEMES (CSV) or default to 'kokosos'
  const allowedSchemes = String(env.APP_SCHEMES || 'kokosos').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean)
  const allowAppScheme = (url: URL) => allowedSchemes.includes(url.protocol.replace(':', '').toLowerCase()) && url.host.toLowerCase() === 'oauth-callback'
  if (provided) {
    try {
      const u = new URL(provided)
      // Accept allowed app scheme callback
      if (allowAppScheme(u)) return u.toString()
      // Accept https with same host as WEB_PUBLIC_BASE
      if (u.protocol === 'https:' && webBase) {
        const wb = new URL(webBase)
        if (u.host.toLowerCase() === wb.host.toLowerCase()) return u.toString()
      }
    } catch {}
  }
  return defaultWeb
}

function buildAuthEmail(kind: AuthEmailKind, link: string, email: string, newEmail?: string, webBase?: string) {
  const wrap = (title: string, body: string, btn: string) => {
    const btnHtml = `<p style="margin:16px 0"><a href="${link}" style="display:inline-block;background:#111827;color:#fff;padding:10px 14px;border-radius:8px;text-decoration:none">${btn}</a></p>`
    const footer = `<p style="color:#6b7280;font-size:12px">このリンクは一定時間で無効になります。覚えがない場合は本メールを破棄してください。</p>`
    const html = `<div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial;line-height:1.7">
      <h2 style="margin:0 0 8px 0">KokoSOS</h2>
      <p>${body}</p>
      ${btnHtml}
      ${footer}
    </div>`
    return { subject: `KokoSOS ${title}`, html, text: `${title}\n${body}\n${link}` }
  }
  switch (kind) {
    case 'confirm_signup':
      return wrap('登録のご確認', '下のボタンからメールアドレスの確認を完了してください。', 'メールアドレスを確認')
    case 'invite':
      return wrap('ご招待', 'KokoSOS への招待が届いています。下のボタンからアカウントを有効化してください。', '招待を受ける')
    case 'magic_link':
    case 'reauth':
      return wrap('かんたんサインイン', '下のボタンからサインインしてください。', 'サインイン')
    case 'change_email_current':
      return wrap('メール変更の確認', 'メール変更の手続きを受け付けました。下のボタンから変更を確定してください。', '変更を確定')
    case 'change_email_new':
      return wrap('新しいメールの確認', '新しいメールアドレスの確認が必要です。下のボタンから確認を完了してください。', '新しいメールを確認')
    case 'reset_password':
      return wrap('パスワード再設定のご案内', '下のボタンからパスワードの再設定を完了してください。', 'パスワードを再設定')
  }
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')
  const bin = atob(b64)
  const bytes = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
  return bytes.buffer
}

async function fcmSendToTokens(env: Env, tokens: string[], msg: PushMessage) {
  if (!tokens.length) return
  const accessToken = await getFcmAccessToken(env)
  const url = `https://fcm.googleapis.com/v1/projects/${env.FCM_PROJECT_ID}/messages:send`
  for (const token of tokens) {
    const body = {
      message: {
        token,
        notification: { title: msg.title, body: msg.body },
        data: msg.data || {},
        apns: { payload: { aps: { category: msg.category || 'general' } } },
      },
    }
    const res = await fetch(url, {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' },
      body: JSON.stringify(body),
    })
    if (!res.ok) {
      // On failure, consider invalidating token later (NotRegistered/Unavailable handling TBD)
      // console.log('fcm_send_fail', token, res.status, await res.text())
    }
  }
}

async function pushNotifySender(env: Env, alertId: string, msg: PushMessage) {
  const sb = supabase(env)
  if (!sb) return
  const a = await sb.select('alerts', 'user_id,type', `id=eq.${encodeURIComponent(alertId)}`, 1)
  if (!a.ok || !a.data.length) return
  const userId = String((a.data[0] as any).user_id)
  const devs = await sb.select('devices', 'fcm_token,platform,valid', `user_id=eq.${encodeURIComponent(userId)}&valid=is.true`)
  if (!devs.ok) return
  const tokens = Array.from(new Set((devs.data as any[]).map((d) => String(d.fcm_token)).filter(Boolean)))
  await fcmSendToTokens(env, tokens, msg)
}

async function pushNotifySenderForReaction(env: Env, alertId: string, preset: string, contactId?: string) {
  const labelMap: Record<string, string> = { ok: 'OK', on_my_way: '向かっています', will_call: '今すぐ連絡します', call_police: '通報しました' }
  let contactLabel: string | null = null
  let alertType: 'emergency' | 'going_home' = 'emergency'
  try {
    // Fetch alert type for mode-specific wording
    try {
      const sb = supabase(env)
      if (sb) {
        const a = await sb.select('alerts', 'type', `id=eq.${encodeURIComponent(alertId)}`, 1)
        if (a.ok && a.data.length > 0) {
          const t = String((a.data[0] as any).type)
          if (t === 'going_home' || t === 'emergency') alertType = t as any
        }
      }
    } catch {}
    if (contactId) {
      const sb = supabase(env)
      if (sb) {
        const res = await sb.select('contacts', 'name,email', `id=eq.${encodeURIComponent(contactId)}`, 1)
        if (res.ok && res.data.length > 0) {
          const c = res.data[0] as any
          contactLabel = (c.name && String(c.name).trim().length > 0) ? String(c.name) : (c.email ? String(c.email).split('@')[0] : null)
        }
      }
    }
  } catch {}
  const label = labelMap[preset] || preset
  const who = contactLabel || '見守り相手'
  // 文言をプリセット別に最適化（送信者アプリでの受け取りを想定し、"共有画面" など送信者が見られないUI言及を避ける）
  let title: string
  let body: string
  switch (preset) {
    case 'ok':
      title = `${who} から「OK」の返信`
      body = (alertType === 'going_home')
        ? '受信済みです。到着まで無理をせず、安全に移動してください。'
        : '返信を受け取りました。必要なときは相手から連絡が入ります。'
      break
    case 'on_my_way':
      title = `${who} から「向かっています」の返信`
      body = '合流予定です。安全な場所でお待ちください。'
      break
    case 'will_call':
      title = `${who} から「今すぐ連絡します」の返信`
      body = 'まもなく電話が入ります。周囲の安全を確保してください。'
      break
    case 'call_police':
      title = `${who} から「通報しました」の連絡`
      body = '安全を最優先に。必要なら緊急通報・連絡を行ってください。'
      break
    default:
      title = `${who} から返信: 「${label}」`
      body = '返信を受け取りました。必要に応じて連絡してください。'
  }
  await pushNotifySender(env, alertId, { title, body, category: 'reaction', data: { alert_id: alertId, preset } })
}

export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext) {
    const path = parsePath(req)
    const method = req.method as Method
    // Preflight CORS
    if (method === 'OPTIONS') {
      const allow = env.CORS_ALLOW_ORIGIN || '*'
      return new Response(null, { status: 204, headers: { ...corsHeaders(allow), ...securityHeaders() } })
    }
    for (const r of routes) {
      const m = path.match(r.pattern)
      if (m && r.method === method) {
        const params: Record<string, string> = {}
        const res = await r.handler({ req, env, ctx, params })
        const allow = env.CORS_ALLOW_ORIGIN || '*'
        const headers = new Headers(res.headers)
        for (const [k, v] of Object.entries(corsHeaders(allow))) headers.set(k, v)
        for (const [k, v] of Object.entries(securityHeaders())) headers.set(k, v)
        return new Response(res.body, { status: res.status, headers })
      }
    }
    if (routes.some((r) => r.pattern.test(path))) return methodNotAllowed()
    return notFound()
  },
}

// -------- Durable Object: AlertHub (WebSocket broadcast)
export class AlertHub {
  state: DurableObjectState
  accepts: number
  broadcasts: number
  constructor(state: DurableObjectState, _env: Env) {
    this.state = state
    this.accepts = 0
    this.broadcasts = 0
    // Auto-respond to ping frames/messages to keep connections alive without waking the DO
    try {
      // @ts-ignore: WebSocketRequestResponsePair is provided by the Workers runtime
      this.state.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping', 'pong'))
    } catch {}
  }
  async fetch(req: Request) {
    const url = new URL(req.url)
    if (url.pathname === '/ws' && (req.headers.get('Upgrade') || '').toLowerCase() === 'websocket') {
      // Create a server/client pair and accept the server side into this Durable Object.
      const pair = new WebSocketPair()
      const client = pair[0]
      const server = pair[1]
      this.state.acceptWebSocket(server)
      this.accepts += 1
      const sockets = this.state.getWebSockets()
      console.log('do_ws_accept', { sockets: sockets.length })
      return new Response(null, { status: 101, webSocket: client })
    }
    if (url.pathname === '/publish' && req.method === 'POST') {
      const text = await req.text()
      const sockets = this.state.getWebSockets()
      console.log('do_publish_broadcast', { sockets: sockets.length })
      this.broadcasts += 1
      for (const ws of sockets) {
        try { ws.send(text) } catch {}
      }
      return new Response('ok')
    }
    if (url.pathname === '/diag') {
      const sockets = this.state.getWebSockets()
      const body = JSON.stringify({ sockets: sockets.length, accepts: this.accepts, broadcasts: this.broadcasts })
      return new Response(body, { headers: { 'content-type': 'application/json' } })
    }
    return new Response('Not Found', { status: 404 })
  }
}

// -------- Durable Object: RateLimiter (fixed-window counters)
export class RateLimiter {
  state: DurableObjectState
  constructor(state: DurableObjectState, _env: Env) {
    this.state = state
  }
  async fetch(req: Request): Promise<Response> {
    const url = new URL(req.url)
    if (url.pathname === '/check') {
      const limit = Number(url.searchParams.get('limit') || '5')
      const windowSec = Number(url.searchParams.get('window') || '60')
      const now = Math.floor(Date.now() / 1000)
      const windowStart = now - (now % windowSec)
      const key = `w:${windowStart}`
      // Use atomic alarm barrier: read-modify-write
      const current = (await this.state.storage.get<number>(key)) || 0
      if (current >= limit) return new Response(JSON.stringify({ allow: false }), { headers: { 'content-type': 'application/json' } })
      await this.state.storage.put(key, current + 1, { expirationTtl: windowSec + 5 })
      return new Response(JSON.stringify({ allow: true }), { headers: { 'content-type': 'application/json' } })
    }
    return new Response('not found', { status: 404 })
  }
}

// -------- Helpers: time/remaining
function computeRemaining(started_at: string, max_duration_sec: number, ended_at?: string | null): number {
  const start = new Date(started_at).getTime()
  const now = Date.now()
  const end = ended_at ? new Date(ended_at).getTime() : null
  const elapsed = Math.floor(((end ?? now) - start) / 1000)
  return Math.max(0, max_duration_sec - elapsed)
}

function clampInt(v: string | null, min: number, max: number, fallback: number) {
  const n = v ? parseInt(v, 10) : NaN
  if (!Number.isFinite(n)) return fallback
  return Math.min(max, Math.max(min, n))
}

// -------- Supabase REST minimal client
function supabase(env: Env) {
  if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) return null
  const base = env.SUPABASE_URL.replace(/\/$/, '') + '/rest/v1'
  const headersBase = {
    apikey: env.SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
  }
  return {
    async insert(table: string, data: Record<string, unknown>) {
      const res = await fetch(`${base}/${table}`, { method: 'POST', headers: { ...headersBase, 'content-type': 'application/json', Prefer: 'return=representation' }, body: JSON.stringify(data) })
      const ok = res.ok
      const dataJson = ok ? await res.json() : null
      return { ok, data: dataJson as any[], error: ok ? null : await res.text() }
    },
    async update(table: string, data: Record<string, unknown>, query: string) {
      const res = await fetch(`${base}/${table}?${query}`, { method: 'PATCH', headers: { ...headersBase, 'content-type': 'application/json', Prefer: 'return=representation' }, body: JSON.stringify(data) })
      const ok = res.ok
      const dataJson = ok ? await res.json() : null
      return { ok, data: dataJson as any[], error: ok ? null : await res.text() }
    },
    async select(table: string, columns: string, query: string, limit?: number) {
      const url = `${base}/${table}?select=${encodeURIComponent(columns)}${query ? `&${query}` : ''}${limit ? `&limit=${limit}` : ''}`
      const res = await fetch(url, { headers: headersBase })
      const ok = res.ok
      const dataJson = ok ? await res.json() : null
      return { ok, data: (dataJson as any[]) || [], error: ok ? null : await res.text() }
    },
    async delete(table: string, query: string) {
      const url = `${base}/${table}?${query}`
      const res = await fetch(url, { method: 'DELETE', headers: headersBase })
      return { ok: res.ok, error: res.ok ? null : await res.text() }
    },
  }
}

// -------- Supabase Auth (JWT RS256) verification and sender extraction
type AuthCheck = { ok: true; userId: string | null } | { ok: false; error: string; status: number }

async function getSenderFromAuth(req: Request, env: Env): Promise<AuthCheck> {
  const requireAuth = (env.REQUIRE_AUTH_SENDER || 'false').toLowerCase() === 'true'
  const authz = req.headers.get('authorization') || req.headers.get('Authorization')
  if (!authz) return requireAuth ? { ok: false, error: 'unauthorized', status: 401 } : { ok: true, userId: null }
  const m = authz.match(/^Bearer\s+(.+)$/i)
  if (!m) return requireAuth ? { ok: false, error: 'unauthorized', status: 401 } : { ok: true, userId: null }
  const token = m[1]
  const verified = await verifySupabaseJwt(token, env).catch(() => null)
  if (!verified) return requireAuth ? { ok: false, error: 'invalid_token', status: 401 } : { ok: true, userId: null }
  const sub = typeof verified.sub === 'string' ? verified.sub : null
  if (!sub) return requireAuth ? { ok: false, error: 'invalid_token', status: 401 } : { ok: true, userId: null }
  return { ok: true, userId: sub }
}

type Jwk = { kid: string; kty: string; alg: string; use?: string; n?: string; e?: string }
let jwksCache: { keys: Jwk[]; fetchedAt: number } | null = null

async function verifySupabaseJwt(token: string, env: Env): Promise<Record<string, unknown> | null> {
  const [hB64, pB64, sB64] = token.split('.')
  if (!hB64 || !pB64 || !sB64) return null
  const header = JSON.parse(new TextDecoder().decode(base64urlToUint8Array(hB64))) as { alg: string; kid?: string }
  if (header.alg !== 'RS256') return null
  const kid = header.kid
  const jwksUrl = env.SUPABASE_JWKS_URL || (env.SUPABASE_URL ? `${env.SUPABASE_URL.replace(/\/$/, '')}/auth/v1/.well-known/jwks.json` : '')
  if (!jwksUrl) return null
  // Fetch/cached JWKS
  const now = Date.now()
  if (!jwksCache || now - jwksCache.fetchedAt > 15 * 60 * 1000) {
    const res = await fetch(jwksUrl)
    if (!res.ok) return null
    const { keys } = (await res.json()) as { keys: Jwk[] }
    jwksCache = { keys, fetchedAt: now }
  }
  const jwk = jwksCache.keys.find((k) => !kid || k.kid === kid)
  if (!jwk || jwk.kty !== 'RSA' || !jwk.n || !jwk.e) return null
  const key = await crypto.subtle.importKey(
    'jwk',
    { kty: 'RSA', n: jwk.n, e: jwk.e, alg: 'RS256', ext: true } as JsonWebKey,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify']
  )
  const data = new TextEncoder().encode(`${hB64}.${pB64}`)
  const sig = base64urlToUint8Array(sB64)
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, sig, data)
  if (!ok) return null
  const payload = JSON.parse(new TextDecoder().decode(base64urlToUint8Array(pB64))) as Record<string, unknown>
  // Basic claim checks
  const issOk = typeof payload.iss === 'string' && env.SUPABASE_URL && (payload.iss as string).startsWith(env.SUPABASE_URL.replace(/\/$/, '') + '/auth/v1')
  const expOk = typeof payload.exp === 'number' ? nowSec() < (payload.exp as number) : true
  if (!issOk || !expOk) return null
  return payload
}

// (replaced by Durable Object: AlertHub)

// -------- Email provider (SES or log)
interface EmailProvider {
  send(input: { to: string; subject: string; html: string; text?: string }): Promise<void>
}

function makeEmailProvider(env: Env): EmailProvider {
  if ((env.EMAIL_PROVIDER || '').toLowerCase() === 'ses') return new SESEmailProvider(env)
  return new LogEmailProvider()
}

class LogEmailProvider implements EmailProvider {
  async send(input: { to: string; subject: string; html: string; text?: string }): Promise<void> {
    console.log('EMAIL (dev log):', input.to, input.subject)
  }
}

class SESEmailProvider implements EmailProvider {
  private env: Env
  constructor(env: Env) { this.env = env }
  async send(input: { to: string; subject: string; html: string; text?: string }): Promise<void> {
    const region = this.env.SES_REGION!
    const endpoint = `https://email.${region}.amazonaws.com/v2/email/outbound-emails` // SESv2
    const body = JSON.stringify({
      FromEmailAddress: this.env.SES_SENDER_EMAIL,
      Destination: { ToAddresses: [input.to] },
      Content: { Simple: { Subject: { Data: input.subject, Charset: 'UTF-8' }, Body: { Html: { Data: input.html, Charset: 'UTF-8' } , ...(input.text ? { Text: { Data: input.text, Charset: 'UTF-8' } } : {}) } } },
    })
    const now = new Date()
    const amzDate = toAmzDate(now)
    const dateStamp = amzDate.slice(0, 8)
    const service = 'ses'
    const method = 'POST'
    const url = new URL(endpoint)
    const canonicalUri = url.pathname
    const canonicalQuerystring = ''
    const host = url.host
    const contentType = 'application/json'
    const payloadHash = await sha256Hex(body)
    // Include x-amz-content-sha256 and content-type in signed headers for stricter SigV4
    const canonicalHeaders =
      `content-type:${contentType}\n` +
      `host:${host}\n` +
      `x-amz-content-sha256:${payloadHash}\n` +
      `x-amz-date:${amzDate}\n`
    const signedHeaders = 'content-type;host;x-amz-content-sha256;x-amz-date'
    const canonicalRequest = `${method}\n${canonicalUri}\n${canonicalQuerystring}\n${canonicalHeaders}\n${signedHeaders}\n${payloadHash}`
    const algorithm = 'AWS4-HMAC-SHA256'
    const credentialScope = `${dateStamp}/${region}/${service}/aws4_request`
    const stringToSign = `${algorithm}\n${amzDate}\n${credentialScope}\n${await sha256Hex(canonicalRequest)}`
    const signingKey = await getSignatureKey(this.env.SES_SECRET_ACCESS_KEY!, dateStamp, region, service)
    const signature = await hmacHex(signingKey, stringToSign)
    const authorizationHeader = `${algorithm} Credential=${this.env.SES_ACCESS_KEY_ID!}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`
    const res = await fetch(endpoint, {
      method,
      headers: {
        'content-type': contentType,
        'x-amz-content-sha256': payloadHash,
        'x-amz-date': amzDate,
        Authorization: authorizationHeader,
      },
      body,
    })
    if (!res.ok) {
      const text = await res.text()
      throw new Error(`SES send failed: ${res.status} ${text}`)
    }
  }
}


function toAmzDate(d: Date) {
  const pad = (n: number, w = 2) => String(n).padStart(w, '0')
  return `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`
}

async function sha256Hex(s: string): Promise<string> {
  const enc = new TextEncoder()
  const digest = await crypto.subtle.digest('SHA-256', enc.encode(s))
  return buf2hex(new Uint8Array(digest))
}

async function hmac(key: CryptoKey, data: string | Uint8Array): Promise<ArrayBuffer> {
  const enc = new TextEncoder()
  const bytes = typeof data === 'string' ? enc.encode(data) : data
  return crypto.subtle.sign('HMAC', key, bytes)
}

function buf2hex(buf: Uint8Array): string {
  return Array.from(buf).map((b) => b.toString(16).padStart(2, '0')).join('')
}

async function importKey(raw: Uint8Array): Promise<CryptoKey> {
  return crypto.subtle.importKey('raw', raw, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
}

async function hmacHex(key: CryptoKey, data: string): Promise<string> {
  const sig = await hmac(key, data)
  return buf2hex(new Uint8Array(sig))
}

async function getSignatureKey(key: string, dateStamp: string, regionName: string, serviceName: string): Promise<CryptoKey> {
  const kDate = await importKey(await hmacRaw(`AWS4${key}`, dateStamp))
  const kRegion = await importKey(await hmacRaw(kDate, regionName))
  const kService = await importKey(await hmacRaw(kRegion, serviceName))
  const kSigning = await importKey(await hmacRaw(kService, 'aws4_request'))
  return kSigning
}

// -------- Debug helpers (dev only)
function isEmailDebug(env: Env): boolean {
  return (env.EMAIL_DEBUG || '').toLowerCase() === 'true'
}

function maskEmail(email: string): string {
  const parts = String(email).split('@')
  if (parts.length !== 2) return '***'
  const [user, domain] = parts
  const u = user ? (user[0] + '***') : '***'
  const d = domain ? (domain[0] + '***') : '***'
  return `${u}@${d}`
}

async function hmacRaw(key: string | CryptoKey, data: string): Promise<Uint8Array> {
  let k: CryptoKey
  if (typeof key === 'string') {
    k = await importKey(new TextEncoder().encode(key))
  } else {
    k = key
  }
  const sig = await hmac(k, data)
  return new Uint8Array(sig)
}

function emailInviteHtmlEmergency(link: string, senderName?: string | null): string {
  const who = senderName && senderName.length > 0 ? `${escapeHtml(senderName)}さんが` : '送信者が'
  const domain = (() => { try { const u = new URL(link); return u.host } catch { return 'kokosos.com' } })()
  return `
  <div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial; line-height:1.7">
    <p style="margin:0 0 8px 0"><strong style="font-size:16px;vertical-align:middle">KokoSOS</strong></p>
    <p><strong>${who}「いま」の状況を共有しています。</strong></p>
    <p>すぐに位置と状態を確認できます。必要に応じて見守りをお願いします。</p>
    <p style="margin:16px 0"><a href="${link}" style="display:inline-block;background:#ef4444;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none">状況を確認する</a></p>
    <p style="color:#6b7280;font-size:13px">このリンクは24時間で自動的に無効になります。覚えがない場合は、このメールを無視してください。配信元: ${escapeHtml(domain)}</p>
  </div>`
}

function emailInviteTextEmergency(link: string, senderName?: string | null): string {
  const who = senderName && senderName.length > 0 ? `${senderName}さんが` : '送信者が'
  return `${who}「いま」の状況をKokoSOSで共有しています。

位置と状態を確認できます（24時間で自動的に無効になります）。
${link}

このメールに覚えがない場合は破棄してください。`
}

function emailInviteHtmlGoingHome(link: string, senderName?: string | null): string {
  const who = senderName && senderName.length > 0 ? `${escapeHtml(senderName)}さんが` : '送信者が'
  const domain = (() => { try { const u = new URL(link); return u.host } catch { return 'kokosos.com' } })()
  return `
  <div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial; line-height:1.7">
    <p style="margin:0 0 8px 0"><strong style="font-size:16px;vertical-align:middle">KokoSOS</strong></p>
    <p><strong>${who}「帰る」共有を開始しました。</strong></p>
    <p>到着までのあいだ、温かく見守ってください。</p>
    <p style="margin:16px 0"><a href="${link}" style="display:inline-block;background:#0ea5e9;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none">現在の様子を見る</a></p>
    <p style="color:#6b7280;font-size:13px">このリンクは24時間で自動的に無効になります。覚えがない場合は、このメールを無視してください。配信元: ${escapeHtml(domain)}</p>
  </div>`
}

function emailInviteTextGoingHome(link: string, senderName?: string | null): string {
  const who = senderName && senderName.length > 0 ? `${senderName}さんが` : '送信者が'
  return `${who}「帰る」共有をKokoSOSで開始しました。

到着までのあいだ、見守りをお願いします（リンクは24時間で自動的に無効になります）。
${link}

このメールに覚えがない場合は破棄してください。`
}

function emailVerifyHtml(link: string, senderName: string | null, _senderAvatarUrl: string | null): string {
  const who = senderName && senderName.length > 0 ? `${escapeHtml(senderName)}さんから` : ''
  const icon = '' // メール内に画像は表示しない方針
  return `
  <div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial; line-height:1.7">
    <p style="margin:0 0 8px 0">${icon}<strong style="font-size:16px;vertical-align:middle">KokoSOS</strong></p>
    <p><strong>${who}KokoSOSの受信者（見守り）依頼が届いています。</strong></p>
    <p>KokoSOSは、送信者が危険を感じたときに最小の操作で信頼できる相手へ通知し、共有中のみ「現在地・状態・残り時間」を共有できるサービスです。</p>
    <p>下のボタンから受信許可を確認してください。許可後は、送信者が共有を開始したときにメールでお知らせします。</p>
    <p style="margin:16px 0"><a href="${link}" style="background:#2563eb;color:#fff;padding:10px 14px;border-radius:6px;text-decoration:none;display:inline-block">受信許可を確認する</a></p>
    <p style="color:#6b7280">リンクは一定時間で無効になります。迷惑メールに入ってしまうことがあるため、kokosos.com からのメールを許可してください。誤って登録された場合は、このメールを無視してください。</p>
    <p style="font-weight:600">送信者を見守ってくださいね。</p>
  </div>`
}

function emailVerifyText(link: string, senderName: string | null): string {
  const who = senderName && senderName.length > 0 ? `${senderName}さんから` : ''
  return `${who}KokoSOSの受信者（見守り）依頼が届いています。\n\n次のリンクから受信許可を確認してください（一定時間で無効になります）。\n${link}\n\n心当たりが無い場合は、このメールを破棄してください。`
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c] as string))
}

// ---------- Avatar upload (Supabase Storage via Workers proxy)
const AVATAR_BUCKET = 'avatars'
const AVATAR_MAX_BYTES = 2 * 1024 * 1024 // 2MB
const ALLOWED_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp'])

// 1) issue short-lived upload URL (to this Worker) with path token
async function handleAvatarUploadURL({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const auth = await getSenderFromAuth(req, env)
  if (!auth.ok || !auth.userId) return json({ error: 'unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const ext = (url.searchParams.get('ext') || 'jpg').toLowerCase()
  const safeExt = ['jpg', 'jpeg', 'png', 'webp'].includes(ext) ? (ext === 'jpg' ? 'jpeg' : ext) : 'jpeg'
  const path = `${auth.userId}/${Date.now()}-${Math.random().toString(36).slice(2)}.${safeExt}`
  const token = await signJwtHs256({ scope: 'avatar_upload', path, exp: nowSec() + 300 }, env.JWT_SECRET)
  return json({ uploadUrl: `/profile/avatar/upload?token=${encodeURIComponent(token)}`, path, expiresIn: 300 })
}

// 2) accept multipart/form-data { file } and forward to Supabase Storage
async function handleAvatarUpload({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const url = new URL(req.url)
  const token = url.searchParams.get('token') || ''
  const payload = await verifyJwtHs256(token, env.JWT_SECRET)
  if (!payload || (payload as any).scope !== 'avatar_upload') return json({ error: 'invalid_token' }, { status: 401 })
  const path = String((payload as any).path || '')
  if (!path) return json({ error: 'invalid_path' }, { status: 400 })
  const form = await req.formData().catch(() => null)
  if (!form) return json({ error: 'invalid_form' }, { status: 400 })
  const file = form.get('file') as unknown as File | null
  if (!file || typeof (file as any).arrayBuffer !== 'function') return json({ error: 'missing_file' }, { status: 400 })
  const contentType = (file as any).type || 'application/octet-stream'
  if (!ALLOWED_TYPES.has(contentType)) return json({ error: 'unsupported_type' }, { status: 400 })
  const buf = await (file as any).arrayBuffer()
  if ((buf as ArrayBuffer).byteLength > AVATAR_MAX_BYTES) return json({ error: 'file_too_large' }, { status: 400 })
  if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) return json({ error: 'server_misconfig' }, { status: 500 })
  const putUrl = `${env.SUPABASE_URL.replace(/\/$/, '')}/storage/v1/object/${encodeURIComponent(AVATAR_BUCKET)}/${encodeURIComponent(path)}`
  const res = await fetch(putUrl, {
    method: 'PUT',
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      'content-type': contentType,
      'x-upsert': 'true',
    },
    body: buf as ArrayBuffer,
  })
  if (!res.ok) {
    const t = await res.text()
    return json({ error: 'storage_put_failed', detail: `${res.status} ${t}` }, { status: 500 })
  }
  return json({ ok: true, path })
}

// 3) commit avatar path into user_metadata (and name if provided)
async function handleAvatarCommit({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const authz = req.headers.get('authorization') || req.headers.get('Authorization')
  if (!authz) return json({ error: 'unauthorized' }, { status: 401 })
  const auth = await getSenderFromAuth(req, env)
  if (!auth.ok || !auth.userId) return json({ error: 'unauthorized' }, { status: auth.status })
  const body = await req.json().catch(() => null)
  if (!body || typeof body.path !== 'string') return json({ error: 'invalid_body' }, { status: 400 })
  const name = typeof body.name === 'string' && body.name.trim().length > 0 ? body.name.trim() : undefined
  const userMeta: Record<string, unknown> = { avatar_url: `${AVATAR_BUCKET}/${body.path}` }
  if (name) userMeta['full_name'] = name
  const adminUrl = `${env.SUPABASE_URL!.replace(/\/$/, '')}/auth/v1/admin/users/${encodeURIComponent(auth.userId)}`
  const res = await fetch(adminUrl, {
    method: 'PUT',
    headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY as string, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` , 'content-type': 'application/json' },
    body: JSON.stringify({ user_metadata: userMeta }),
  })
  if (!res.ok) {
    const t = await res.text()
    return json({ error: 'update_user_failed', detail: `${res.status} ${t}` }, { status: 500 })
  }
  return json({ ok: true })
}
function emailArrivalHtml(): string {
  return `<div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial">
  <p>到着を確認しました。ご安心ください。</p>
</div>`
}

function emailArrivalText(): string {
  return `KokoSOS: 到着を確認しました。ご安心ください。\n\nこのメールに覚えがない場合は破棄してください。`
}

// -------- Ensure a default dev user exists and return its id
async function ensureDefaultUserId(sb: ReturnType<typeof supabase>, env: Env): Promise<string> {
  const email = env.DEFAULT_USER_EMAIL || 'dev@kokosos.local'
  const found = await sb.select('users', 'id', `email=eq.${encodeURIComponent(email)}`, 1)
  if (found.ok && found.data.length > 0) return found.data[0].id as string
  const ins = await sb.insert('users', { email })
  if (ins.ok && ins.data.length > 0) return ins.data[0].id as string
  // Fallback: try again select, else throw
  const re = await sb.select('users', 'id', `email=eq.${encodeURIComponent(email)}`, 1)
  if (re.ok && re.data.length > 0) return re.data[0].id as string
  throw new Error('failed_to_ensure_default_user')
}

// Ensure a users row exists with given id (Supabase Auth user id)
async function ensureUserExists(sb: ReturnType<typeof supabase>, userId: string): Promise<void> {
  // Try select by id
  const found = await sb.select('users', 'id', `id=eq.${encodeURIComponent(userId)}`, 1)
  if (found.ok && found.data.length > 0) return
  // Insert with explicit id; emailは不明な場合はnull
  await sb.insert('users', { id: userId as any }).catch(() => undefined)
}
