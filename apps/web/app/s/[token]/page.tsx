'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import mapboxgl from 'mapbox-gl'
import 'mapbox-gl/dist/mapbox-gl.css'

export const runtime = 'edge'

type AlertState = {
  type: 'emergency' | 'going_home'
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
  const mapRef = useRef<HTMLDivElement | null>(null)
  const mapInstance = useRef<mapboxgl.Map | null>(null)
  const markerRef = useRef<mapboxgl.Marker | null>(null)
  const circleSourceId = 'accuracy-circle'
  const routeSourceId = 'route-line'
  const routeCoordsRef = useRef<[number, number][]>([])
  const mapboxToken = process.env.NEXT_PUBLIC_MAPBOX_TOKEN
  const [mapError, setMapError] = useState<string | null>(null)
  const lastEventAtRef = useRef<number>(0)
  const [remainingLocal, setRemainingLocal] = useState<number>(0)
  const [toast, setToast] = useState<string | null>(null)
  const toastTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    let closed = false
    async function load() {
      try {
        const res = await fetch(`${apiBase}/public/alert/${encodeURIComponent(token)}`)
        if (!res.ok) throw new Error('failed to load')
        const data = (await res.json()) as AlertState
        if (!closed) setState(data)
        // Load initial history (route) only for emergency mode
        try {
          if (data.type !== 'going_home') {
            const r = await fetch(`${apiBase}/public/alert/${encodeURIComponent(token)}/locations?limit=200&order=asc`)
            if (r.ok) {
              const j = (await r.json()) as { items: { lat: number; lng: number }[] }
              routeCoordsRef.current = j.items.map((x) => [x.lng, x.lat])
              // If map is ready, reflect immediately
              if (mapInstance.current) updateRoute(mapInstance.current)
            }
          }
        } catch {}
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
    let stopped = false
    let retryMs = 1000
    function connect() {
      if (stopped) return
      const es = new EventSource(`${apiBase}/public/alert/${encodeURIComponent(token)}/stream`)
      esRef.current = es
      es.onmessage = (ev) => {
        try {
          const evt = JSON.parse(ev.data)
          lastEventAtRef.current = Date.now()
          if (evt.type === 'location') setState((s) => (s && s.type !== 'going_home' ? { ...s, latest: evt.latest } : s))
          if (evt.type === 'status') setState((s) => (s ? { ...s, status: evt.status } : s))
          if (evt.type === 'extended') {
            setState((s) => (s ? { ...s, remaining_sec: typeof evt.remaining_sec === 'number' ? evt.remaining_sec : s.remaining_sec } : s))
            try { if (toastTimerRef.current) clearTimeout(toastTimerRef.current) } catch {}
            const addedMin = typeof evt.added_sec === 'number' ? Math.max(1, Math.round(evt.added_sec / 60)) : null
            setToast(addedMin ? `+${addedMin}分延長されました` : '共有時間が延長されました')
            toastTimerRef.current = setTimeout(() => setToast(null), 3000)
          }
          if (evt.type === 'reaction') {
            try { if (toastTimerRef.current) clearTimeout(toastTimerRef.current) } catch {}
            const label = labelForPreset(String(evt.preset || 'reply'))
            setToast(`返信: ${label}`)
            toastTimerRef.current = setTimeout(() => setToast(null), 2500)
          }
          // reset backoff on successful message
          retryMs = 1000
        } catch {}
      }
      es.onerror = () => {
        es.close()
        if (stopped) return
        const wait = retryMs
        retryMs = Math.min(retryMs * 2, 30000)
        setTimeout(connect, wait)
      }
    }
    connect()
    return () => {
      stopped = true
      esRef.current?.close()
    }
  }, [apiBase, token])

  // Polling fallback: SSEが8秒以上沈黙している時だけ5秒間隔で最新を取得
  useEffect(() => {
    let active = true
    const id = setInterval(async () => {
      if (!active) return
      const silentFor = Date.now() - (lastEventAtRef.current || 0)
      if (lastEventAtRef.current !== 0 && silentFor < 8000) return
      try {
        const res = await fetch(`${apiBase}/public/alert/${encodeURIComponent(token)}`)
        if (!res.ok) return
        const data = (await res.json()) as AlertState
        setState((prev) => {
          const prevTs = prev?.latest ? new Date(prev.latest.captured_at).getTime() : 0
          const nextTs = data.latest ? new Date(data.latest.captured_at).getTime() : 0
          if (nextTs > prevTs && data.latest) {
            appendRoute(data.latest.lng, data.latest.lat)
            if (mapInstance.current) updateRoute(mapInstance.current)
            return prev ? { ...prev, latest: data.latest } : data
          }
          return prev ?? data
        })
      } catch {}
    }, 5000)
    return () => {
      active = false
      clearInterval(id)
    }
  }, [apiBase, token])

  const remaining = useMemo(() => (state ? Math.max(0, state.remaining_sec) : 0), [state])

  // Drive a 1-second ticking countdown locally; resync when server value changes
  useEffect(() => {
    setRemainingLocal(remaining)
    if (remaining <= 0) return
    let val = remaining
    const id = setInterval(() => {
      val -= 1
      setRemainingLocal(Math.max(0, val))
    }, 1000)
    return () => clearInterval(id)
  }, [remaining])

  // Initialize Mapbox map when token and container are ready (skip for going_home)
  useEffect(() => {
    if (!mapRef.current) return
    if (!mapboxToken || /^(?:YOUR_|xxxx|placeholder)/i.test(mapboxToken)) { setMapError('地図トークンが未設定です（NEXT_PUBLIC_MAPBOX_TOKEN）'); return }
    if (state?.type === 'going_home') return
    if (mapInstance.current) return
    mapboxgl.accessToken = mapboxToken
    const map = new mapboxgl.Map({
      container: mapRef.current,
      style: 'mapbox://styles/mapbox/streets-v12',
      center: [139.767, 35.681],
      zoom: 14,
    })
    map.addControl(new mapboxgl.NavigationControl({ showCompass: false }), 'top-right')
    map.on('load', () => {
      // Localize labels to Japanese where available
      try { localizeLabelsToJapanese(map) } catch {}
      // Prepare accuracy circle source/layer
      if (!map.getSource(circleSourceId)) {
        map.addSource(circleSourceId, { type: 'geojson', data: emptyCircle() })
        map.addLayer({
          id: 'accuracy-fill',
          type: 'fill',
          source: circleSourceId,
          paint: { 'fill-color': '#3b82f6', 'fill-opacity': 0.15 },
        })
        map.addLayer({
          id: 'accuracy-outline',
          type: 'line',
          source: circleSourceId,
          paint: { 'line-color': '#3b82f6', 'line-width': 1 },
        })
      }
      // Prepare route line source/layer
      if (!map.getSource(routeSourceId)) {
        map.addSource(routeSourceId, { type: 'geojson', data: emptyRoute() })
        map.addLayer({
          id: 'route-line',
          type: 'line',
          source: routeSourceId,
          paint: { 'line-color': '#2563eb', 'line-width': 3 },
          layout: { 'line-cap': 'round', 'line-join': 'round' },
        })
      }
      // Place marker if we have initial location
      const latest = state?.latest
      if (latest) {
        upsertMarker(latest.lng, latest.lat)
        updateCircle(map, latest.lat, latest.lng, latest.accuracy_m ?? 0)
        appendRoute(latest.lng, latest.lat)
        updateRoute(map)
        map.jumpTo({ center: [latest.lng, latest.lat], zoom: 15 })
      }
    })
    map.on('error', (ev) => {
      try {
        const err = (ev as any).error
        if (err && typeof err.message === 'string' && /401|unauthorized|forbidden|token/i.test(err.message)) {
          setMapError('地図トークンが無効です（Mapboxのアクセストークンと許可ドメインを確認）')
        } else {
          setMapError('地図の読み込みに失敗しました')
        }
      } catch { setMapError('地図の読み込みに失敗しました') }
    })
    mapInstance.current = map
    return () => {
      map.remove()
      mapInstance.current = null
      markerRef.current = null
    }
  }, [mapboxToken, state?.latest])

  // Update map when latest location changes
  useEffect(() => {
    const latest = state?.latest
    const map = mapInstance.current
    if (!latest || !map) return
    upsertMarker(latest.lng, latest.lat)
    updateCircle(map, latest.lat, latest.lng, latest.accuracy_m ?? 0)
    appendRoute(latest.lng, latest.lat)
    updateRoute(map)
    // Smoothly move for subsequent updates
    map.easeTo({ center: [latest.lng, latest.lat], duration: 800 })
  }, [state?.latest])

  function upsertMarker(lng: number, lat: number) {
    if (!markerRef.current) {
      markerRef.current = new mapboxgl.Marker({ color: '#ef4444' }).setLngLat([lng, lat]).addTo(mapInstance.current!)
    } else {
      markerRef.current.setLngLat([lng, lat])
    }
  }

  function updateCircle(map: mapboxgl.Map, lat: number, lng: number, accuracy_m: number) {
    const source = map.getSource(circleSourceId) as mapboxgl.GeoJSONSource | undefined
    if (!source) return
    const radius = Math.max(accuracy_m || 0, 0)
    const data = radius > 0 ? circleGeoJSON(lat, lng, radius) : emptyCircle()
    source.setData(data)
  }

  function emptyCircle(): GeoJSON.FeatureCollection<GeoJSON.Polygon> {
    return { type: 'FeatureCollection', features: [] }
  }

  function circleGeoJSON(lat: number, lng: number, radiusMeters: number): GeoJSON.FeatureCollection<GeoJSON.Polygon> {
    const points = 64
    const coords: [number, number][] = []
    const R = 6378137
    for (let i = 0; i <= points; i++) {
      const theta = (i / points) * 2 * Math.PI
      const dx = (radiusMeters * Math.cos(theta)) / (R * Math.cos((lat * Math.PI) / 180))
      const dy = radiusMeters * Math.sin(theta) / R
      const lngOffset = (dx * 180) / Math.PI
      const latOffset = (dy * 180) / Math.PI
      coords.push([lng + lngOffset, lat + latOffset])
    }
    return {
      type: 'FeatureCollection',
      features: [
        {
          type: 'Feature',
          geometry: { type: 'Polygon', coordinates: [coords] },
          properties: {},
        },
      ],
    }
  }

  function emptyRoute(): GeoJSON.FeatureCollection<GeoJSON.LineString> {
    return { type: 'FeatureCollection', features: [] }
  }

  function appendRoute(lng: number, lat: number) {
    const coords = routeCoordsRef.current
    const last = coords[coords.length - 1]
    // Avoid pushing duplicate points
    if (!last || last[0] !== lng || last[1] !== lat) {
      coords.push([lng, lat])
      // Keep last 200 points to bound memory
      if (coords.length > 200) coords.shift()
    }
  }

  function updateRoute(map: mapboxgl.Map) {
    const coords = routeCoordsRef.current
    const src = map.getSource(routeSourceId) as mapboxgl.GeoJSONSource | undefined
    if (!src) return
    if (coords.length < 2) {
      src.setData(emptyRoute())
      return
    }
    const data: GeoJSON.FeatureCollection<GeoJSON.LineString> = {
      type: 'FeatureCollection',
      features: [
        { type: 'Feature', geometry: { type: 'LineString', coordinates: coords }, properties: {} },
      ],
    }
    src.setData(data)
  }

  // Replace text labels with Japanese names where available
  function localizeLabelsToJapanese(map: mapboxgl.Map) {
    const style = map.getStyle()
    if (!style?.layers) return
    for (const layer of style.layers) {
      if (layer.type !== 'symbol') continue
      const id = layer.id
      // text-field があるレイヤのみ対象
      // 既存の複雑なformat式のレイヤには適用しない（盾アイコン等を避ける）
      const tf = (layer as any).layout?.['text-field']
      if (!tf) continue
      // シールド系やハイウェイ番号などはスキップ
      if (id.includes('shield') || id.includes('motorway') && String(tf).includes('{reflen}')) continue
      try {
        map.setLayoutProperty(id, 'text-field', [
          'coalesce',
          ['get', 'name_ja'],
          ['get', 'name']
        ])
      } catch {}
    }
  }

  return (
    <main style={{ padding: 16, display: 'grid', gap: 12 }}>
      <h1 style={{ margin: 0, fontSize: 22 }}>KokoSOS</h1>
      {!state && !error && <p>読み込み中...</p>}
      {error && <p style={{ color: 'crimson' }}>{error}</p>}
      {state && (
        <section style={{ display: 'grid', gap: 8 }}>
          <div>ステータス: {labelStatus(state.status)}</div>
          <div>残り時間: {formatDuration(remainingLocal)}</div>
          <div>
            最終更新: {state.latest ? new Date(state.latest.captured_at).toLocaleString() : '—'} / バッテリー:{' '}
            {state.latest?.battery_pct ?? '—'}%
          </div>
          {state.type === 'going_home' ? (
            <div style={{ padding: 12, background: '#fff7ed', border: '1px solid #fed7aa', borderRadius: 8, color: '#7c2d12' }}>
              帰るモード: 出発と到着のみ通知します（位置のライブ共有はありません）
            </div>
          ) : (
            <div style={{ height: 320, borderRadius: 8, overflow: 'hidden', position: 'relative', background: '#e5e7eb' }}>
              {mapError && (
                <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', zIndex: 1, background: 'rgba(255,255,255,0.8)' }}>
                  <div style={{ color: '#111827', padding: 12, textAlign: 'center', lineHeight: 1.6 }}>{mapError}</div>
                </div>
              )}
              <div ref={mapRef} style={{ width: '100%', height: '100%' }} />
            </div>
          )}
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <a href="tel:0000000000" style={btn()}>電話</a>
            {/* プリセット返信（複数） */}
            <button style={btn()} onClick={() => react('ok')} disabled={!state.permissions.can_reply}>OK</button>
            <button style={btn()} onClick={() => react('on_my_way')} disabled={!state.permissions.can_reply}>向かっています</button>
            <button style={btn()} onClick={() => react('will_call')} disabled={!state.permissions.can_reply}>今すぐ連絡します</button>
            <button style={btn({ variant: 'danger' })} onClick={() => react('call_police')} disabled={!state.permissions.can_reply}>通報しました</button>
            <a href="tel:110" style={btn({ variant: 'danger' })}>110へ電話</a>
          </div>
        </section>
      )}
      {toast && (
        <div style={{ position: 'fixed', left: 0, right: 0, bottom: 16, display: 'grid', placeItems: 'center', pointerEvents: 'none' }}>
          <div style={{ background: 'rgba(17,24,39,0.95)', color: 'white', padding: '10px 14px', borderRadius: 8, boxShadow: '0 4px 12px rgba(0,0,0,0.25)' }}>
            {toast}
          </div>
        </div>
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

  function labelForPreset(preset: string): string {
    const map: Record<string, string> = {
      ok: 'OK',
      on_my_way: '向かっています',
      will_call: '今すぐ連絡します',
      call_police: '通報しました',
    }
    return map[preset] || preset
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
