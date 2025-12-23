import type { Metadata } from 'next';
import Link from 'next/link';
import { ThemeProvider } from '@/components/ThemeProvider';
import { ThemeToggle } from '@/components/ThemeToggle';
import SessionProvider from '@/components/SessionProvider';
import UserMenu from '@/components/UserMenu';
import './globals.css';

export const metadata: Metadata = {
  title: 'Book Vault - Personal Audiobook Library',
  description: 'Your personal audiobook collection, organized and accessible',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body>
        <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
          <SessionProvider>
            {/* Global Header */}
            <header className="bg-white dark:bg-gray-900 shadow-sm sticky top-0 z-50 transition-colors">
              <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
                <div className="flex items-start justify-between">
                  <Link href="/" className="block hover:opacity-80 transition-opacity">
                    <h1 className="text-3xl font-bold text-gray-900 dark:text-white">
                      📚 Book Vault
                    </h1>
                    <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
                      Your personal audiobook library
                    </p>
                  </Link>
                  <div className="flex items-center gap-4">
                    <UserMenu />
                    <ThemeToggle />
                  </div>
                </div>
              </div>
            </header>

            {children}
          </SessionProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
