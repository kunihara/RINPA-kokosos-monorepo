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

  return (
    <main style={{ padding: 24, display: 'grid', gap: 16 }}>
      <h1>KokoSOS</h1>
      <p>メール確認を完了しました。</p>
      <p>アプリに戻るを押してください。</p>
      <button onClick={openApp} style={{ padding: '10px 14px', background: '#111827', color: 'white', borderRadius: 8, border: 'none' }}>アプリに戻る</button>
      {attempted && (
        <p style={{ color: '#6b7280', fontSize: 12 }}>自動で開かない場合は上のボタンをタップしてください。</p>
      )}
    </main>
  )
}
