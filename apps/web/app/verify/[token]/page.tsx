'use client'

import { useEffect, useState } from 'react'

export const runtime = 'edge'

export default function VerifyPage(props: any) {
  const token: string = props?.params?.token || ''
  const apiBase = process.env.NEXT_PUBLIC_API_BASE || ''
  const appDeepLink = (process.env.NEXT_PUBLIC_APP_SCHEME || 'kokosos') + '://oauth-callback'

  const [status, setStatus] = useState<'loading' | 'ok' | 'error'>('loading')
  const [message, setMessage] = useState<string>('')

  useEffect(() => {
    let cancelled = false
    async function run() {
      try {
        const res = await fetch(`${apiBase}/public/verify/${encodeURIComponent(token)}`)
        const j = await res.json().catch(() => ({} as any))
        if (cancelled) return
        if (res.ok && j?.ok) {
          setStatus('ok')
          setMessage('受信許可を確認しました。')
        } else {
          setStatus('error')
          setMessage(j?.error ? `エラー: ${j.error}` : '無効なリンクです。')
        }
      } catch (e) {
        if (cancelled) return
        setStatus('error')
        setMessage('確認に失敗しました。時間をおいて再度お試しください。')
      }
    }
    if (token) run()
    return () => { cancelled = true }
  }, [apiBase, token])

  return (
    <main style={{ padding: 24, maxWidth: 600, margin: '0 auto' }}>
      <h1>KokoSOS</h1>
      {status === 'loading' && <p>確認中です…</p>}
      {status !== 'loading' && <p>{message}</p>}
      <div style={{ marginTop: 16 }}>
        <a href={appDeepLink} style={{ color: '#2563eb' }}>アプリに戻る</a>
      </div>
    </main>
  )
}
