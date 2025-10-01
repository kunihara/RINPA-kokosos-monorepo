export type AlertStatus = 'active' | 'ended' | 'timeout'

export type PublicAlert = {
  status: AlertStatus
  remaining_sec: number
  latest: null | { lat: number; lng: number; accuracy_m: number | null; battery_pct: number | null; captured_at: string }
  permissions: { can_call: boolean; can_reply: boolean; can_call_police: boolean }
}

export type StreamEvent =
  | { type: 'hello'; ts: number }
  | { type: 'keepalive'; ts: number }
  | { type: 'location'; latest: NonNullable<PublicAlert['latest']> }
  | { type: 'status'; status: AlertStatus }
