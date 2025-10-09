"use client"

import { Suspense } from 'react'
import { useMemo, useState } from 'react'
import { useSearchParams } from 'next/navigation'
import Turnstile from '../../components/Turnstile'

export const dynamic = 'force-dynamic'

export default function Page() {
  return (
    <Suspense fallback={<main style={{ padding: 16 }}><div>Loading…</div></main>}>
      <AuthEmailDiagInner />
    </Suspense>
  )
}

function AuthEmailDiagInner() {
  const apiBase = process.env.NEXT_PUBLIC_API_BASE || ''
  const sp = useSearchParams()
  const siteKeyOverride = sp.get('site_key') || undefined
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [token, setToken] = useState<string | null>(null)
  const [kind, setKind] = useState<'reset' | 'magic' | 'signup'>('reset')
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<string | null>(null)
  const [mode, setMode] = useState<'managed' | 'non-interactive' | 'invisible'>('non-interactive')

  const endpoint = useMemo(() => {
    switch (kind) {
      case 'reset': return '/auth/email/reset'
      case 'magic': return '/auth/email/magic'
      case 'signup': return '/auth/signup'
    }
  }, [kind])

  async function submit() {
    setMsg(null)
    if (!email) { setMsg('メールアドレスを入力してください'); return }
    if (!token) { setMsg('Turnstileを完了してください'); return }
    if (kind === 'signup' && password.length < 8) { setMsg('パスワードは8文字以上を入力してください'); return }
    setBusy(true)
    try {
      const body: any = { email, turnstile_token: token }
      if (kind === 'signup') body.password = password
      const r = await fetch(apiBase + endpoint, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) })
      if (!r.ok) { setMsg(`エラー: ${r.status}`); return }
      setMsg('送信しました（結果は常に ok で返ります）')
    } catch (e: any) {
      setMsg(String(e))
    } finally { setBusy(false) }
  }

  const btnDisabled = busy || !email || !token || (kind === 'signup' && password.length < 8)

  return (
    <main style={{ padding: 16, display: 'grid', gap: 12 }}>
      <h1 style={{ margin: 0, fontSize: 20 }}>Auth Email Diagnostics</h1>
      <div style={{ display: 'grid', gap: 8, maxWidth: 460 }}>
        {!process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY && (
          <div style={{ padding: 8, border: '1px solid #f59e0b', background: '#fffbeb', color: '#92400e', borderRadius: 6, fontSize: 13 }}>
            NEXT_PUBLIC_TURNSTILE_SITE_KEY が未設定です。Cloudflare Pagesの環境変数に設定した後、再デプロイしてください。
          </div>
        )}
        <label style={{ display: 'grid', gap: 4 }}>
          <span style={{ fontSize: 13, color: '#374151' }}>メールアドレス</span>
          <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" style={input()} />
        </label>
        {kind === 'signup' && (
          <label style={{ display: 'grid', gap: 4 }}>
            <span style={{ fontSize: 13, color: '#374151' }}>パスワード（8文字以上）</span>
            <input value={password} onChange={(e) => setPassword(e.target.value)} type="password" placeholder="********" style={input()} />
          </label>
        )}
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          <label><input type="radio" name="kind" checked={kind === 'reset'} onChange={() => setKind('reset')} /> パスワード再設定</label>
          <label><input type="radio" name="kind" checked={kind === 'magic'} onChange={() => setKind('magic')} /> マジックリンク</label>
          <label><input type="radio" name="kind" checked={kind === 'signup'} onChange={() => setKind('signup')} /> サインアップ</label>
        </div>
        <div style={{ display: 'grid', gap: 6 }}>
          <div style={{ display: 'flex', gap: 12, alignItems: 'center', flexWrap: 'wrap' }}>
            <span style={{ fontSize: 12, color: '#374151' }}>ウィジェット モード:</span>
            <label><input type="radio" name="mode" checked={mode==='managed'} onChange={() => setMode('managed')} /> 管理対象</label>
            <label><input type="radio" name="mode" checked={mode==='non-interactive'} onChange={() => setMode('non-interactive')} /> 非インタラクティブ</label>
            <label><input type="radio" name="mode" checked={mode==='invisible'} onChange={() => setMode('invisible')} /> 非表示</label>
          </div>
          <Turnstile onToken={setToken} mode={mode} siteKey={siteKeyOverride || undefined} />
          <div style={{ fontSize: 12, color: token ? '#065f46' : '#6b7280', marginTop: 4 }}>
            {token ? 'Turnstileトークン取得済み' : 'ウィジェットを完了すると送信できます。'}
          </div>
        </div>
        <button onClick={submit} disabled={btnDisabled} style={btn()}>送信</button>
        {msg && <div style={{ color: '#111827', fontSize: 14 }}>{msg}</div>}
      </div>
    </main>
  )
}

function input() {
  return { padding: 8, border: '1px solid #d1d5db', borderRadius: 6 } as React.CSSProperties
}
function btn() {
  return { background: '#111827', color: 'white', border: 0, borderRadius: 6, padding: '10px 14px', cursor: 'pointer' } as React.CSSProperties
}
