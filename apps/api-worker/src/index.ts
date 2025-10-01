export interface Env {
  JWT_SECRET: string
  SUPABASE_URL?: string
  SUPABASE_SERVICE_ROLE_KEY?: string
  SES_REGION?: string
  SES_ACCESS_KEY_ID?: string
  SES_SECRET_ACCESS_KEY?: string
  SES_SENDER_EMAIL?: string
  CORS_ALLOW_ORIGIN?: string
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
  { method: 'POST', pattern: /^\/alert\/start$/, handler: handleAlertStart },
  { method: 'POST', pattern: /^\/alert\/(\w+)\/update$/, handler: handleAlertUpdate },
  { method: 'POST', pattern: /^\/alert\/(\w+)\/stop$/, handler: handleAlertStop },
  { method: 'POST', pattern: /^\/alert\/(\w+)\/revoke$/, handler: handleAlertRevoke },
  { method: 'GET', pattern: /^\/public\/alert\/([^/]+)$/, handler: handlePublicAlert },
  { method: 'GET', pattern: /^\/public\/alert\/([^/]+)\/stream$/, handler: handlePublicAlertStream },
  { method: 'POST', pattern: /^\/public\/alert\/([^/]+)\/react$/, handler: handlePublicAlertReact },
]

async function handleAlertStart({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const body = await req.json().catch(() => null)
  if (!body) return json({ error: 'invalid_json' }, { status: 400 })
  const initial = {
    lat: body.lat as number | undefined,
    lng: body.lng as number | undefined,
    accuracy_m: body.accuracy_m as number | undefined,
    battery_pct: body.battery_pct as number | undefined,
    type: (body.type as string | undefined) || 'emergency',
    max_duration_sec: (body.max_duration_sec as number | undefined) ?? 3600,
  }
  if (typeof initial.lat !== 'number' || typeof initial.lng !== 'number') return json({ error: 'invalid_location' }, { status: 400 })
  const alertId = crypto.randomUUID()
  const shareToken = await signJwtHs256(
    {
      alert_id: alertId,
      scope: 'viewer',
      exp: nowSec() + 24 * 3600,
    },
    env.JWT_SECRET,
  )
  const startedAt = new Date().toISOString()
  const state = {
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

async function handleAlertUpdate({ req }: Parameters<RouteHandler>[0]): Promise<Response> {
  const body = await req.json().catch(() => null)
  if (!body) return json({ error: 'invalid_json' }, { status: 400 })
  return json({ ok: true })
}

async function handleAlertStop(): Promise<Response> {
  return json({ status: 'ended' })
}

async function handleAlertRevoke(): Promise<Response> {
  return json({ revoked: true })
}

async function handlePublicAlert({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const token = decodeURIComponent(req.url.split('/public/alert/')[1] || '')
  const payload = await withJwtFromPathToken(req, env, token)
  if (!payload) return json({ error: 'invalid_token' }, { status: 401 })
  const data = {
    status: 'active',
    remaining_sec: 3600,
    latest: null as
      | null
      | { lat: number; lng: number; accuracy_m: number | null; battery_pct: number | null; captured_at: string },
    permissions: { can_call: true, can_reply: true, can_call_police: true },
  }
  return json(data)
}

async function handlePublicAlertStream({ req, env, ctx }: Parameters<RouteHandler>[0]): Promise<Response> {
  const token = decodeURIComponent(req.url.split('/public/alert/')[1]?.replace(/\/stream$/, '') || '')
  const payload = await withJwtFromPathToken(req, env, token)
  if (!payload) return json({ error: 'invalid_token' }, { status: 401 })
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      const enc = new TextEncoder()
      function send(evt: unknown) {
        controller.enqueue(enc.encode(`data: ${JSON.stringify(evt)}\n\n`))
      }
      send({ type: 'hello', ts: Date.now() })
      const id = setInterval(() => send({ type: 'keepalive', ts: Date.now() }), 25000)
      const timeout = setTimeout(() => {
        send({ type: 'end' })
        controller.close()
        clearInterval(id)
      }, 5 * 60 * 1000)
      ;(controller as unknown as { _cleanup?: () => void })._cleanup = () => {
        clearInterval(id)
        clearTimeout(timeout)
      }
    },
    cancel() {
      /* no-op */
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

async function handlePublicAlertReact({ req, env }: Parameters<RouteHandler>[0]): Promise<Response> {
  const token = decodeURIComponent(req.url.split('/public/alert/')[1]?.replace(/\/react$/, '') || '')
  const payload = await withJwtFromPathToken(req, env, token)
  if (!payload) return json({ error: 'invalid_token' }, { status: 401 })
  const body = await req.json().catch(() => null)
  if (!body || typeof body.preset !== 'string') return json({ error: 'invalid_body' }, { status: 400 })
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
