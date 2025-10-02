'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import mapboxgl from 'mapbox-gl'
import 'mapbox-gl/dist/mapbox-gl.css'

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
  const mapRef = useRef<HTMLDivElement | null>(null)
  const mapInstance = useRef<mapboxgl.Map | null>(null)
  const markerRef = useRef<mapboxgl.Marker | null>(null)
  const circleSourceId = 'accuracy-circle'
  const routeSourceId = 'route-line'
  const routeCoordsRef = useRef<[number, number][]>([])
  const mapboxToken = process.env.NEXT_PUBLIC_MAPBOX_TOKEN

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

  // Initialize Mapbox map when token and container are ready
  useEffect(() => {
    if (!mapRef.current) return
    if (!mapboxToken) return
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
          <div style={{ height: 320, borderRadius: 8, overflow: 'hidden', position: 'relative', background: '#e5e7eb' }}>
            {!mapboxToken && (
              <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', zIndex: 1, background: 'rgba(255,255,255,0.8)' }}>
                <div style={{ color: '#111827' }}>地図トークンが未設定です（NEXT_PUBLIC_MAPBOX_TOKEN）</div>
              </div>
            )}
            <div ref={mapRef} style={{ width: '100%', height: '100%' }} />
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
