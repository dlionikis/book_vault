# syntax=docker/dockerfile:1

# ============================================
# Stage 1: Dependencies
# ============================================
FROM node:24-alpine AS deps
WORKDIR /app

# Install dependencies needed for native modules (bcrypt) and OpenSSL for Prisma
RUN apk add --no-cache libc6-compat python3 make g++ openssl

# Copy package files
COPY package.json package-lock.json ./
COPY prisma ./prisma/

# Install dependencies
RUN npm ci

# ============================================
# Stage 2: Builder
# ============================================
FROM node:24-alpine AS builder
WORKDIR /app

# Install OpenSSL for Prisma during build (needed for static page generation)
RUN apk add --no-cache openssl libc6-compat

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Set environment for build
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production

# Generate the Prisma client. This runs in the builder (not deps) because
# Prisma 7 emits into the app source tree (lib/generated/prisma), which the
# `COPY . .` above would otherwise clobber.
RUN npx prisma generate

# Build the application
RUN npm run build

# ============================================
# Stage 3: Runner (Production)
# ============================================
FROM node:24-alpine AS runner
WORKDIR /app

# Install runtime dependencies for bcrypt, OpenSSL for Prisma, and FFmpeg for chapter extraction
RUN apk add --no-cache libc6-compat openssl ffmpeg

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Create non-root user for security
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy built application
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Copy the Prisma schema (used by `prisma migrate deploy` via ECS Exec).
# The generated client is NOT copied here: Prisma 7 emits it into the app source
# tree (lib/generated/prisma), so Next's standalone tracer bundles it already.
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/prisma.config.ts ./prisma.config.ts

# Amazon's public RDS CA bundle. Prisma 7 connects through the pg driver, which
# verifies the RDS server certificate against this trust anchor (lib/db-ssl.ts).
# NODE_EXTRA_CA_CERTS covers the Prisma CLI, which reads trust roots from the
# environment rather than from our adapter options.
COPY --from=builder /app/certs ./certs
ENV NODE_EXTRA_CA_CERTS=/app/certs/rds-global-bundle.pem

USER nextjs

# Port 8080 - must match App Runner configuration
EXPOSE 8080
ENV PORT=8080
ENV HOSTNAME="0.0.0.0"

# Use node server.js for standalone Next.js builds (npm start requires full node_modules)
CMD ["node", "server.js"]
