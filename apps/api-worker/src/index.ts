export interface Env {
  JWT_SECRET: string
  SUPABASE_URL?: string
  SUPABASE_SERVICE_ROLE_KEY?: string
  SES_REGION?: string
  SES_ACCESS_KEY_ID?: string
  SES_SECRET_ACCESS_KEY?: string
  SES_SENDER_EMAIL?: string
  CORS_ALLOW_ORIGIN?: string
  WEB_PUBLIC_BASE?: string
  EMAIL_PROVIDER?: string
  DEFAULT_USER_EMAIL?: string
  ALERT_HUB: DurableObjectNamespace
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
]

async function handleHealth({ env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const mask = (v?: string) => (v ? `${v.slice(0, 4)}…(${v.length})` : null)
  const body = {
    ok: true,
    has: {
      JWT_SECRET: !!env.JWT_SECRET,
      SUPABASE_URL: !!env.SUPABASE_URL,
      SUPABASE_SERVICE_ROLE_KEY: !!env.SUPABASE_SERVICE_ROLE_KEY,
    },
    env: {
      CORS_ALLOW_ORIGIN: env.CORS_ALLOW_ORIGIN || null,
      WEB_PUBLIC_BASE: env.WEB_PUBLIC_BASE || null,
      EMAIL_PROVIDER: env.EMAIL_PROVIDER || null,
      DEFAULT_USER_EMAIL: env.DEFAULT_USER_EMAIL || null,
      SUPABASE_URL_preview: env.SUPABASE_URL || null,
      SUPABASE_SERVICE_ROLE_KEY_preview: env.SUPABASE_SERVICE_ROLE_KEY ? `${(env.SUPABASE_SERVICE_ROLE_KEY as string).slice(0,4)}…` : null,
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

async function handleAlertStart({ req, env, ctx }: Parameters<RouteHandler>[0]): Promise<Response> {
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
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  // Create alert row
  const userId = await ensureDefaultUserId(sb, env)
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
  // Send emails if recipients provided
  if (initial.recipients.length > 0 && env.WEB_PUBLIC_BASE) {
    const emailer = makeEmailProvider(env)
    for (const to of initial.recipients) {
      const contactId = crypto.randomUUID()
      const token = await signJwtHs256({ alert_id: alertId, contact_id: contactId, scope: 'viewer', exp: nowSec() + 24 * 3600 }, env.JWT_SECRET)
      const link = `${env.WEB_PUBLIC_BASE.replace(/\/$/, '')}/s/${encodeURIComponent(token)}`
      ctx.waitUntil(emailer.send({ to, subject: 'KokoSOS 共有リンク', html: emailInviteHtml(link) }))
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

async function handleAlertUpdate({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
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
  const m = req.url.match(/\/alert\/([^/]+)\/stop/)
  if (!m) return notFound()
  const alertId = m[1]
  const sb = supabase(env)
  if (!sb) return json({ error: 'server_misconfig' }, { status: 500 })
  const ended_at = new Date().toISOString()
  await sb.update('alerts', { status: 'ended', ended_at }, `id=eq.${alertId}`)
  const stub = env.ALERT_HUB.get(env.ALERT_HUB.idFromName(alertId))
  await stub.fetch('https://do/publish', { method: 'POST', body: JSON.stringify({ type: 'status', status: 'ended' }) })
  return json({ status: 'ended' })
}

async function handleAlertExtend({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
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
  // Save
  await sb.insert('reactions', { alert_id: alertId, contact_id: contactId, preset })
  // Broadcast
  try {
    const stub = env.ALERT_HUB.get(env.ALERT_HUB.idFromName(alertId))
    await stub.fetch('https://do/publish', { method: 'POST', body: JSON.stringify({ type: 'reaction', preset, ts: Date.now() }) })
  } catch {}
  return json({ ok: true })
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
  }
}

// (replaced by Durable Object: AlertHub)

// -------- Email provider (SES or log)
interface EmailProvider {
  send(input: { to: string; subject: string; html: string }): Promise<void>
}

function makeEmailProvider(env: Env): EmailProvider {
  if (env.EMAIL_PROVIDER === 'ses') return new SESEmailProvider(env)
  return new LogEmailProvider()
}

class LogEmailProvider implements EmailProvider {
  async send(input: { to: string; subject: string; html: string }): Promise<void> {
    console.log('EMAIL (dev log):', input.to, input.subject)
  }
}

class SESEmailProvider implements EmailProvider {
  private env: Env
  constructor(env: Env) { this.env = env }
  async send(input: { to: string; subject: string; html: string }): Promise<void> {
    const region = this.env.SES_REGION!
    const endpoint = `https://email.${region}.amazonaws.com/v2/email/outbound-emails` // SESv2
    const body = JSON.stringify({
      FromEmailAddress: this.env.SES_SENDER_EMAIL,
      Destination: { ToAddresses: [input.to] },
      Content: { Simple: { Subject: { Data: input.subject, Charset: 'UTF-8' }, Body: { Html: { Data: input.html, Charset: 'UTF-8' } } } },
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
    const canonicalHeaders = `host:${host}\n` + `x-amz-date:${amzDate}\n`
    const signedHeaders = 'host;x-amz-date'
    const payloadHash = await sha256Hex(body)
    const canonicalRequest = `${method}\n${canonicalUri}\n${canonicalQuerystring}\n${canonicalHeaders}\n${signedHeaders}\n${payloadHash}`
    const algorithm = 'AWS4-HMAC-SHA256'
    const credentialScope = `${dateStamp}/${region}/${service}/aws4_request`
    const stringToSign = `${algorithm}\n${amzDate}\n${credentialScope}\n${await sha256Hex(canonicalRequest)}`
    const signingKey = await getSignatureKey(this.env.SES_SECRET_ACCESS_KEY!, dateStamp, region, service)
    const signature = await hmacHex(signingKey, stringToSign)
    const authorizationHeader = `${algorithm} Credential=${this.env.SES_ACCESS_KEY_ID!}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`
    const res = await fetch(endpoint, { method, headers: { 'content-type': 'application/json', host, 'x-amz-date': amzDate, Authorization: authorizationHeader }, body })
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

function emailInviteHtml(link: string): string {
  return `<div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial">
  <p>KokoSOS からの緊急共有リンクです。</p>
  <p><a href="${link}">${link}</a></p>
  <p>このリンクは24時間で失効します。</p>
</div>`
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
