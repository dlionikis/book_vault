/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  images: {
    // Scoped to the hosts we actually serve covers from. Previously `**`, which
    // GHSA-9g9p-9gw9-jx7f (Image Optimizer remotePatterns DoS) specifically warns
    // against — a wildcard lets the optimizer be pointed at arbitrary hosts. The
    // full fix ships in Next 16 (see docs/plans/dependency-major-upgrades.md);
    // tightening the allowlist mitigates the exposure now on Next 14.
    remotePatterns: [
      // Production: presigned S3 URLs (virtual-hosted style), e.g.
      // book-vault-media.s3.us-east-1.amazonaws.com / book-vault-media.s3.amazonaws.com
      {
        protocol: 'https',
        hostname: '*.s3.*.amazonaws.com',
      },
      {
        protocol: 'https',
        hostname: '*.s3.amazonaws.com',
      },
      // Development: local /api/images route
      {
        protocol: 'http',
        hostname: 'localhost',
        port: '3000',
      },
      {
        protocol: 'http',
        hostname: '127.0.0.1',
        port: '3000',
      },
    ],
  },
  // serverActions graduated from `experimental` to a stable top-level option in
  // Next 15+.
  serverActions: {
    bodySizeLimit: '2mb',
  },
};

module.exports = nextConfig;
