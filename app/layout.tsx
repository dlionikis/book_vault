import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Book Vault - Personal Audiobook Library',
  description: 'Your personal audiobook collection, organized and accessible',
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
