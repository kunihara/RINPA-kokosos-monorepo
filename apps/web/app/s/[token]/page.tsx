'use client'

import { useEffect, useMemo, useRef, useState } from 'react'

export const runtime = 'edge'

type AlertState = {
  status: 'active' | 'ended' | 'timeout'
  remaining_sec: number
  latest: null | { lat: number; lng: number; accuracy_m: number | null; battery_pct: number | null; captured_at: string }
  permissions: { can_call: boolean; can_reply: boolean; can_call_police: boolean }
}

export default function ReceiverPage({ params }: any) {
  const { token } = (params || {}) as { token: string }
  const [state, setState] = useState<AlertState | null>(null)
  const [error, setError] = useState<string | null>(null)
  const apiBase = process.env.NEXT_PUBLIC_API_BASE || ''
  const esRef = useRef<EventSource | null>(null)

  useEffect(() => {
    let closed = false
    async function load() {
      try {
        const res = await fetch(`${apiBase}/public/alert/${encodeURIComponent(token)}`)
        if (!res.ok) throw new Error('failed to load')
        const data = (await res.json()) as AlertState
        if (!closed) setState(data)
      } catch (e) {
        if (!closed) setError('読み込みに失敗しました')
      }
    }
    load()
    return () => {
      closed = true
    }
  }, [apiBase, token])

  useEffect(() => {
    const es = new EventSource(`${apiBase}/public/alert/${encodeURIComponent(token)}/stream`)
    esRef.current = es
    es.onmessage = (ev) => {
      try {
        const evt = JSON.parse(ev.data)
        if (evt.type === 'location') setState((s) => (s ? { ...s, latest: evt.latest } : s))
        if (evt.type === 'status') setState((s) => (s ? { ...s, status: evt.status } : s))
      } catch {}
    }
    es.onerror = () => {
      es.close()
    }
    return () => es.close()
  }, [apiBase, token])

  const remaining = useMemo(() => (state ? Math.max(0, state.remaining_sec) : 0), [state])

  return (
    <main style={{ padding: 16, display: 'grid', gap: 12 }}>
      <h1 style={{ margin: 0, fontSize: 22 }}>KokoSOS</h1>
      {!state && !error && <p>読み込み中...</p>}
      {error && <p style={{ color: 'crimson' }}>{error}</p>}
      {state && (
        <section style={{ display: 'grid', gap: 8 }}>
          <div>ステータス: {labelStatus(state.status)}</div>
          <div>残り時間: {formatDuration(remaining)}</div>
          <div>
            最終更新: {state.latest ? new Date(state.latest.captured_at).toLocaleString() : '—'} / バッテリー:{' '}
            {state.latest?.battery_pct ?? '—'}%
          </div>
          <div style={{ height: 280, background: '#f3f4f6', borderRadius: 8, display: 'grid', placeItems: 'center' }}>
            <div>
              地図プレースホルダ
              {state.latest && (
                <div style={{ fontSize: 12, opacity: 0.7 }}>
                  lat {state.latest.lat.toFixed(5)} / lng {state.latest.lng.toFixed(5)} ±
                  {state.latest.accuracy_m ?? '—'}m
                </div>
              )}
            </div>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <a href="tel:0000000000" style={btn()}>電話</a>
            <button style={btn()} onClick={() => react('ok')} disabled={!state.permissions.can_reply}>
              プリセット返信
            </button>
            <a href="tel:110" style={btn({ variant: 'danger' })}>
              110へ電話
            </a>
          </div>
        </section>
      )}
    </main>
  )

  async function react(preset: string) {
    try {
      await fetch(`${apiBase}/public/alert/${encodeURIComponent(token)}/react`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ preset }),
      })
    } catch {}
  }
}

function labelStatus(s: AlertState['status']): string {
  if (s === 'active') return '共有中'
  if (s === 'ended') return '終了'
  return '期限切れ'
}

function formatDuration(sec: number) {
  const m = Math.floor(sec / 60)
  const s = sec % 60
  return `${m}分${s.toString().padStart(2, '0')}秒`
}

function btn(opts?: { variant?: 'default' | 'danger' }) {
  const v = opts?.variant || 'default'
  const bg = v === 'danger' ? '#ef4444' : '#3b82f6'
  return {
    background: bg,
    color: 'white',
    border: 0,
    borderRadius: 8,
    padding: '10px 14px',
    textDecoration: 'none',
    display: 'inline-block',
  } as React.CSSProperties
}
