'use client'

import Script from 'next/script'
import { useCallback, useEffect, useRef, useState } from 'react'

declare global {
  interface Window {
    turnstile?: {
      render: (el: HTMLElement, opts: any) => string
      reset: (id?: string) => void
      remove: (id?: string) => void
    }
  }
}

type Props = {
  siteKey?: string
  onToken?: (token: string | null) => void
  mode?: 'managed' | 'non-interactive' | 'invisible'
}

export default function Turnstile({ siteKey, onToken, mode = 'managed' }: Props) {
  const key = siteKey || process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY || ''
  const rootRef = useRef<HTMLDivElement | null>(null)
  const [widgetId, setWidgetId] = useState<string | null>(null)
  const [ready, setReady] = useState(false)

  const reset = useCallback(() => {
    try { window.turnstile?.reset(widgetId || undefined) } catch {}
    onToken?.(null)
  }, [widgetId, onToken])

  useEffect(() => {
    if (!ready) return
    const el = rootRef.current
    if (!el || !key || !window.turnstile) return
    // Clear previous if any
    try { if (widgetId) window.turnstile?.remove(widgetId) } catch {}
    const id = window.turnstile.render(el, {
      sitekey: key,
      callback: (token: string) => onToken?.(token),
      'expired-callback': reset,
      'error-callback': reset,
      theme: 'auto',
      appearance: mode === 'invisible' ? 'interaction-only' : 'always',
    })
    setWidgetId(id)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, key, mode])

  return (
    <>
      <Script
        src="https://challenges.cloudflare.com/turnstile/v0/api.js"
        async
        defer
        onReady={() => setReady(true)}
      />
      <div ref={rootRef} />
    </>
  )
}

