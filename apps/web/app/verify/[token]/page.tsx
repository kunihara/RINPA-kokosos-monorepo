'use client'

import { useEffect, useState } from 'react'

export const runtime = 'edge'

export default function VerifyPage(props: any) {
  const token: string = props?.params?.token || ''
  const apiBase = process.env.NEXT_PUBLIC_API_BASE || ''

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
    <main style={{ padding: 24, maxWidth: 720, margin: '0 auto', lineHeight: 1.7 }}>
      <h1>KokoSOS</h1>
      {status === 'loading' && <p>確認中です…</p>}
      {status !== 'loading' && (
        <>
          <h2 style={{ fontSize: 22, fontWeight: 700, marginTop: 12 }}>{message || '受信許可の確認'}</h2>
          {status === 'ok' && (
            <section style={{ marginTop: 12, color: '#374151' }}>
              <p>今後、この送信者が共有を開始するとメールでお知らせします。</p>
              <p>メール内のリンクから、共有中のみ「現在地・状態・残り時間」を確認できます（リンクは一定時間で無効になります）。</p>
              <p>共有を停止すると閲覧できなくなります。アプリやアカウントは不要です。</p>
              <p>迷惑メールに入る場合があるため、kokosos.com からのメールを許可してください。</p>
              <p style={{ fontWeight: 600, marginTop: 8 }}>送信者を見守ってくださいね。</p>
            </section>
          )}
          {status === 'error' && (
            <section style={{ marginTop: 12, color: '#6b7280' }}>
              <p>リンクが無効または期限切れの可能性があります。送信者に再送を依頼してください。</p>
            </section>
          )}
        </>
      )}
    </main>
  )
}
