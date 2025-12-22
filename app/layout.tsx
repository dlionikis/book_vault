import type { Metadata } from 'next';
import Link from 'next/link';
import './globals.css';

export const metadata: Metadata = {
  title: 'Book Vault - Personal Audiobook Library',
  description: 'Your personal audiobook collection, organized and accessible',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        {/* Global Header */}
        <header className="bg-white shadow-sm sticky top-0 z-50">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
            <Link href="/" className="block hover:opacity-80 transition-opacity">
              <h1 className="text-3xl font-bold text-gray-900">📚 Book Vault</h1>
              <p className="mt-1 text-sm text-gray-600">Your personal audiobook library</p>
            </Link>
          </div>
        </header>

        {children}
      </body>
    </html>
  );
}
