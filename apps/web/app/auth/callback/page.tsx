'use client'

import { useEffect, useMemo, useState } from 'react'

export default function AuthCallbackPage() {
  const [attempted, setAttempted] = useState(false)
  // Decide app scheme per environment domain. Fallback to 'kokosos'.
  const scheme = (() => {
    if (typeof window === 'undefined') return 'kokosos://oauth-callback'
    const host = window.location.host
    if (host.includes('-dev')) return 'kokosos-dev://oauth-callback'
    if (host.includes('-stage')) return 'kokosos-stage://oauth-callback'
    return 'kokosos://oauth-callback'
  })()
  const hash = typeof window !== 'undefined' ? window.location.hash : ''
  const search = typeof window !== 'undefined' ? window.location.search : ''
  const params = useMemo(() => (hash && hash.startsWith('#') ? hash : ''), [hash])
  useEffect(() => {
    const url = scheme + (params || '')
    // Try immediate deep-link; if blocked, user can tap the button below.
    try {
      window.location.href = url
    } catch {}
    const id = setTimeout(() => setAttempted(true), 800)
    return () => clearTimeout(id)
  }, [params])

  const openApp = () => {
    const url = scheme + (params || '')
    window.location.href = url
  }

  // Derive flow type from URL hash or search
  const flow = useMemo(() => {
    // Prefer hash params
    if (params) {
      const q = new URLSearchParams(params.replace(/^#/, ''))
      const t = q.get('type') || q.get('flow')
      if (t) return t.toLowerCase()
    }
    // Fallback: query params
    if (search) {
      const q2 = new URLSearchParams(search.replace(/^\?/, ''))
      const t2 = (q2.get('type') || q2.get('flow'))
      if (t2) return t2.toLowerCase()
    }
    return null
  }, [params, search])

  return (
    <main style={{ padding: 24, display: 'grid', gap: 16 }}>
      <h1>KokoSOS</h1>
      {flow === 'recovery' ? (
        <>
          <p>パスワード再設定の手続きです。</p>
          <p>「アプリに戻る」を押して新しいパスワードを設定してください。</p>
        </>
      ) : (
        <>
          <p>手続きが完了しました。</p>
          <p>アプリに戻るを押してください（パスワード再設定の場合もこのまま進めます）。</p>
        </>
      )}
      <button onClick={openApp} style={{ padding: '10px 14px', background: '#111827', color: 'white', borderRadius: 8, border: 'none' }}>アプリに戻る</button>
      {attempted && (
        <p style={{ color: '#6b7280', fontSize: 12 }}>自動で開かない場合は上のボタンをタップしてください。</p>
      )}
    </main>
  )
}
