# syntax=docker/dockerfile:1.7
# ─────────────────────────────────────────────────────────────────────────────
# Familienplaner — Next.js (apps/web) → Coolify (Port 3000, persistentes Volume /data)
# Stage 1 baut die Next.js-App (standalone), Stage 2 ist die schlanke Runtime.
# ─────────────────────────────────────────────────────────────────────────────
FROM node:24-bookworm AS builder
WORKDIR /app

# Build-Tools für native Module (better-sqlite3), falls kein Prebuilt vorliegt.
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ \
 && rm -rf /var/lib/apt/lists/*

# Dependencies zuerst — besseres Layer-Caching (Workspace-Manifeste).
COPY package.json package-lock.json ./
COPY apps/web/package.json apps/web/package.json
RUN npm ci

# Rest kopieren + bauen (standalone Output ab Monorepo-Root).
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1 \
    NEXT_OUTPUT_STANDALONE=1
RUN npm run build -w @familienplaner/web

# ─────────────────────────────────────────────────────────────────────────────
FROM node:24-bookworm-slim AS runner
WORKDIR /app

# curl für den HEALTHCHECK
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production \
    PORT=3000 \
    HOSTNAME=0.0.0.0 \
    NEXT_TELEMETRY_DISABLED=1 \
    DATA_DIR=/data

# Next-standalone spiegelt das Monorepo-Layout ab dem Tracing-Root wider.
COPY --from=builder /app/apps/web/.next/standalone ./
COPY --from=builder /app/apps/web/.next/static ./apps/web/.next/static
COPY --from=builder /app/apps/web/public ./apps/web/public

# Non-Root-User (uid/gid 1001) + persistentes Datenverzeichnis.
RUN addgroup --system --gid 1001 app \
 && adduser --system --uid 1001 --ingroup app --home /app --shell /usr/sbin/nologin app \
 && mkdir -p /data \
 && chown -R app:app /data /app

# Coolify/GitHub liefern SOURCE_COMMIT als Build-Arg → /version + Sentry-Release.
ARG SOURCE_COMMIT=unknown
ENV APP_GIT_SHA=$SOURCE_COMMIT

USER app
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -fsS http://localhost:${PORT}/healthz || exit 1

CMD ["node", "apps/web/server.js"]
