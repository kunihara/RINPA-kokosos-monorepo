'use client'

import { useEffect, useMemo, useRef, useState } from 'react'

export const runtime = 'edge'

export default function SSEDiagPage() {
  const apiBase = process.env.NEXT_PUBLIC_API_BASE || ''
  const [token, setToken] = useState('')
  const [connected, setConnected] = useState(false)
  const [messages, setMessages] = useState<string[]>([])
  const [diag, setDiag] = useState<{ sockets?: number; accepts?: number; broadcasts?: number } | null>(null)
  const esRef = useRef<EventSource | null>(null)
  const [alertId, setAlertId] = useState<string | null>(null)

  function log(line: string) {
    setMessages((prev) => [new Date().toLocaleTimeString() + ' ' + line, ...prev].slice(0, 200))
  }

  async function resolveAlertId(tok: string) {
    try {
      const r = await fetch(`${apiBase}/_diag/resolve/${encodeURIComponent(tok)}`)
      if (!r.ok) return null
      const j = await r.json()
      return (j && j.alert_id) ? String(j.alert_id) : null
    } catch { return null }
  }

  async function refreshDiagByAlert(id: string) {
    try {
      const r = await fetch(`${apiBase}/_diag/alert/${encodeURIComponent(id)}`)
      if (!r.ok) return
      const j = await r.json()
      setDiag(j)
    } catch {}
  }

  async function ping() {
    const id = alertId || await resolveAlertId(token)
    if (!id) { log('alert_id が解決できません'); return }
    await fetch(`${apiBase}/_diag/alert/${encodeURIComponent(id)}/publish`, { method: 'POST' })
    log('published diagnostic event')
    await refreshDiagByAlert(id)
  }

  function connect() {
    if (!token) return
    try { esRef.current?.close() } catch {}
    const es = new EventSource(`${apiBase}/public/alert/${encodeURIComponent(token)}/stream`)
    esRef.current = es
    setConnected(true)
    log('SSE connecting...')
    es.onmessage = (ev) => {
      log(`message: ${ev.data}`)
    }
    es.onerror = () => {
      log('SSE error/closed')
      setConnected(false)
      es.close()
    }
  }

  function disconnect() {
    try { esRef.current?.close() } catch {}
    setConnected(false)
    log('SSE disconnected')
  }

  async function onResolve() {
    const id = await resolveAlertId(token)
    setAlertId(id)
    if (id) await refreshDiagByAlert(id)
  }

  return (
    <main style={{ padding: 16, display: 'grid', gap: 12 }}>
      <h1 style={{ margin: 0, fontSize: 20 }}>SSE Diagnostics</h1>
      <div style={{ display: 'grid', gap: 8 }}>
        <input
          placeholder="token を貼り付け"
          value={token}
          onChange={(e) => setToken(e.target.value)}
          style={{ padding: 8, border: '1px solid #d1d5db', borderRadius: 6 }}
        />
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          <button onClick={connect} disabled={!token || connected} style={btn()}>Connect SSE</button>
          <button onClick={disconnect} disabled={!connected} style={btn({ variant: 'secondary' })}>Disconnect</button>
          <button onClick={onResolve} disabled={!token} style={btn({ variant: 'secondary' })}>Resolve alert_id</button>
          <button onClick={ping} disabled={!token} style={btn({ variant: 'danger' })}>Publish test event</button>
        </div>
        {alertId && (
          <div style={{ fontSize: 13, color: '#374151' }}>alert_id: {alertId}</div>
        )}
        {diag && (
          <div style={{ fontSize: 13, color: '#374151' }}>sockets: {diag.sockets} / accepts: {diag.accepts} / broadcasts: {diag.broadcasts}</div>
        )}
      </div>
      <section>
        <h2 style={{ margin: '12px 0 8px 0', fontSize: 16 }}>Messages</h2>
        <div style={{ border: '1px solid #e5e7eb', borderRadius: 6, padding: 8, maxHeight: 240, overflow: 'auto', fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', fontSize: 12 }}>
          {messages.length === 0 ? <div style={{ color: '#6b7280' }}>No messages yet</div> : messages.map((m, i) => (<div key={i}>{m}</div>))}
        </div>
      </section>
    </main>
  )
}

function btn(opts?: { variant?: 'primary' | 'secondary' | 'danger' }) {
  const v = opts?.variant || 'primary'
  const bg = v === 'danger' ? '#ef4444' : v === 'secondary' ? '#6b7280' : '#3b82f6'
  return {
    background: bg,
    color: 'white',
    border: 0,
    borderRadius: 6,
    padding: '8px 12px',
    cursor: 'pointer',
  } as React.CSSProperties
}

