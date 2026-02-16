import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Privacy Policy - Book Vault',
  description: 'Privacy policy for the Book Vault audiobook library application',
};

export default function PrivacyPolicyPage() {
  return (
    <main className="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
      <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-8">Privacy Policy</h1>
      <p className="text-sm text-gray-500 dark:text-gray-400 mb-8">
        Last updated: February 15, 2026
      </p>

      <div className="prose dark:prose-invert max-w-none space-y-6 text-gray-700 dark:text-gray-300">
        <section>
          <h2 className="text-xl font-semibold text-gray-900 dark:text-white mt-8 mb-3">
            Overview
          </h2>
          <p>
            Book Vault is a personal audiobook library application for managing and streaming your
            audiobook collection. We are committed to protecting your privacy. This policy explains
            what information we collect, how we use it, and your rights regarding that information.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold text-gray-900 dark:text-white mt-8 mb-3">
            Information We Collect
          </h2>
          <h3 className="text-lg font-medium text-gray-800 dark:text-gray-200 mt-4 mb-2">
            Account Information
          </h3>
          <p>
            Your account is created by an administrator. We store your username and a password,
            which is securely hashed using industry-standard methods and never stored in plain text.
          </p>
          <h3 className="text-lg font-medium text-gray-800 dark:text-gray-200 mt-4 mb-2">
            Usage Data
          </h3>
          <p>
            We store your listening progress, bookmarks, and library preferences so you can resume
            playback across sessions and devices. This data is associated with your account and is
            not shared with any third parties.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold text-gray-900 dark:text-white mt-8 mb-3">
            Information We Do Not Collect
          </h2>
          <ul className="list-disc pl-6 space-y-2">
            <li>We do not use analytics or tracking services.</li>
            <li>We do not collect device identifiers or advertising data.</li>
            <li>We do not sell, rent, or share your personal information with third parties.</li>
            <li>We do not collect location data.</li>
          </ul>
        </section>

        <section>
          <h2 className="text-xl font-semibold text-gray-900 dark:text-white mt-8 mb-3">
            Biometric Authentication
          </h2>
          <p>
            The iOS app supports Face ID and Touch ID for convenient login. Biometric data is
            processed entirely on your device by Apple&apos;s Local Authentication framework. Book
            Vault never receives, transmits, or stores your biometric data.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold text-gray-900 dark:text-white mt-8 mb-3">
            Cookies and Sessions
          </h2>
          <p>
            We use a session cookie to keep you signed in. This cookie contains an encrypted
            authentication token and is required for the application to function. We do not use any
            third-party cookies or tracking cookies.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold text-gray-900 dark:text-white mt-8 mb-3">
            Data Storage
          </h2>
          <p>
            Your account data and listening progress are stored on our servers. Audiobook files
            downloaded through the iOS app are stored locally on your device and can be removed at
            any time through the app&apos;s settings.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold text-gray-900 dark:text-white mt-8 mb-3">
            Data Deletion
          </h2>
          <p>
            You may request deletion of your account and all associated data at any time by
            contacting us. Upon deletion, all personal information, listening history, and
            preferences will be permanently removed from our servers.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold text-gray-900 dark:text-white mt-8 mb-3">
            Changes to This Policy
          </h2>
          <p>
            We may update this privacy policy from time to time. Any changes will be reflected on
            this page with an updated revision date.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold text-gray-900 dark:text-white mt-8 mb-3">Contact</h2>
          <p>
            If you have questions about this privacy policy or your data, please contact us at{' '}
            <a
              href="mailto:privacy@lionikis.com"
              className="text-blue-600 dark:text-blue-400 hover:underline"
            >
              privacy@lionikis.com
            </a>
            .
          </p>
        </section>
      </div>
    </main>
  );
}
