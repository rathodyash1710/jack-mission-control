import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Jack Mission Control',
  description: 'Mission Control Dashboard for Jack Clawdbot Agent',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}
