###
# Multi-stage Dockerfile for agar.io
# - Builds with Node.js
# - Produces a minimal distroless image (includes CA certs for HTTPS)
# - Runs as non-root
# - Supports build metadata injection
###

ARG NODE_VERSION=18
# NOTE: Use an exact Node version. Do not use wildcards like 18.x; Docker Hub tags do not support that.

#############################
# Builder stage
#############################
FROM node:${NODE_VERSION}-bookworm AS builder

WORKDIR /src

# Copy package files
COPY package.json package-lock.json* ./

# Install dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy application files
COPY . .

# Build application (if needed)
RUN npm run build || true

#############################
# Final (minimal) stage
#############################
FROM node:${NODE_VERSION}-alpine

# Install CA certificates and curl for healthcheck
RUN apk add --no-cache ca-certificates curl

# Create non-root user (Alpine uses addgroup/adduser; use 1001 to avoid conflict with node's 1000)
RUN addgroup -g 1001 -S appuser && adduser -u 1001 -S -G appuser appuser

WORKDIR /app

# Copy application files from builder
COPY --from=builder --chown=appuser:appuser /src /app

# Change ownership to non-root user
RUN chown -R appuser:appuser /app

USER appuser

# Build-time metadata (optional; overridable via --build-arg)
ARG VCS_REF="unknown"
ARG BUILD_DATE=""
ARG VERSION="dev"

# Set environment variables
ENV NODE_ENV=production
ENV PORT=3000
ENV VCS_REF=${VCS_REF}
ENV BUILD_DATE=${BUILD_DATE}
ENV VERSION=${VERSION}

EXPOSE 3000

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:3000/ || exit 1

ENTRYPOINT ["npm", "start"]
CMD []

# Example build:
#   docker build -t ghcr.io/bariiss/agar.io:dev \
#     --build-arg VCS_REF=$(git rev-parse --short HEAD) \
#     --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
#     --build-arg VERSION=dev .
# Multi-arch build (requires buildx):
#   docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/bariiss/agar.io:dev --push .
