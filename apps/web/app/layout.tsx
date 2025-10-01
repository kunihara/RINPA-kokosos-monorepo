export const metadata = {
  title: 'KokoSOS',
  description: 'Emergency location sharing',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ja">
      <body style={{ fontFamily: 'system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial', margin: 0 }}>
        {children}
      </body>
    </html>
  )
}
