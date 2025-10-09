'use client'

import { useEffect, useMemo, useState } from 'react'

export const runtime = 'edge'

export default function AuthConfirmPage() {
  const [attempted, setAttempted] = useState(false)
  const search = typeof window !== 'undefined' ? window.location.search : ''
  const params = useMemo(() => new URLSearchParams((search || '').replace(/^\?/, '')), [search])
  const type = (params.get('type') || '').toLowerCase()
  const next = params.get('next') || ''
  const hash = typeof window !== 'undefined' ? (window.location.hash || '') : ''

  useEffect(() => {
    if (!next) return
    try { window.location.href = next + (hash || '') } catch {}
    const id = setTimeout(() => setAttempted(true), 800)
    return () => clearTimeout(id)
  }, [next])

  const openApp = () => { if (next) window.location.href = next + (hash || '') }

  return (
    <main style={{ padding: 24, display: 'grid', gap: 16 }}>
      <h1>KokoSOS</h1>
      {type === 'recovery' ? (
        <>
          <p>パスワード再設定の手続きです。</p>
          {next ? (
            <>
              <p>「アプリに戻る」を押して新しいパスワードを設定してください。</p>
              <button onClick={openApp} style={{ padding: '10px 14px', background: '#111827', color: 'white', borderRadius: 8, border: 'none' }}>アプリに戻る</button>
              {attempted && (
                <p style={{ color: '#6b7280', fontSize: 12 }}>自動で開かない場合は上のボタンをタップしてください。</p>
              )}
            </>
          ) : (
            <p>アプリに戻るリンクが見つかりませんでした。メールのリンクを再度お試しください。</p>
          )}
        </>
      ) : (
        <>
          <p>メール確認を完了しました。</p>
          {next ? (
            <>
              <p>「アプリに戻る」を押してください。</p>
              <button onClick={openApp} style={{ padding: '10px 14px', background: '#111827', color: 'white', borderRadius: 8, border: 'none' }}>アプリに戻る</button>
              {attempted && (
                <p style={{ color: '#6b7280', fontSize: 12 }}>自動で開かない場合は上のボタンをタップしてください。</p>
              )}
            </>
          ) : null}
        </>
      )}
    </main>
  )
}
