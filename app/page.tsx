export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center p-24">
      <div className="text-center">
        <h1 className="text-4xl font-bold mb-4">
          📚 Book Vault
        </h1>
        <p className="text-xl text-gray-600 mb-8">
          Your Personal Audiobook Library
        </p>
        <div className="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded">
          <p className="font-bold">✅ Next.js is running!</p>
          <p className="text-sm mt-2">Ready to start building</p>
        </div>
      </div>
    </main>
  )
}
