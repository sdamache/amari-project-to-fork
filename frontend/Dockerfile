# Multi-stage Dockerfile for Frontend Service
# Optimized for Cloud Run deployment with backend proxy

# Stage 1: Build the application
FROM node:20-slim AS builder

WORKDIR /app

# Copy package files first for better caching
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production=false

# Copy the rest of the application code
COPY . .

# Build with API pointing to /api (proxied through nginx)
# This ensures frontend talks to its own nginx which proxies to backend
ENV VITE_API_URL=/api

# Build the application
RUN npm run build

# Stage 2: Serve with Nginx (with backend proxy)
FROM nginx:alpine

# Install curl for health checks and gettext for envsubst
RUN apk add --no-cache curl gettext

# Create non-root user
RUN adduser -D -s /bin/sh appuser

# Copy nginx template to custom location (not /etc/nginx/templates to avoid default envsubst)
COPY <<'EOF' /etc/nginx/nginx-template.conf
server {
    listen 8080;
    server_name localhost;

    root /usr/share/nginx/html;
    index index.html;

    # Health check endpoint
    location /health {
        access_log off;
        return 200 'healthy';
        add_header Content-Type text/plain;
    }

    # API proxy to backend (secured via Cloud Run IAM)
    # BACKEND_URL is injected at runtime via environment variable
    location /api/ {
        # Proxy to backend, stripping /api prefix
        proxy_pass ${BACKEND_URL}/;

        # Forward headers
        proxy_set_header Host $proxy_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        # Timeout settings for LLM processing (can take 30+ seconds)
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;

        # Buffer settings
        proxy_buffering on;
        proxy_buffer_size 16k;
        proxy_buffers 4 32k;

        # Handle large file uploads
        client_max_body_size 50M;
    }

    # SPA routing - serve index.html for all routes
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
}
EOF

# Copy the built assets from the builder stage
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy startup script that processes nginx template with envsubst
# Note: We only substitute BACKEND_URL to avoid replacing nginx variables like $uri
COPY <<'STARTUP' /docker-entrypoint.d/10-envsubst-backend.sh
#!/bin/sh
set -e

# Default backend URL for local development
: "${BACKEND_URL:=http://localhost:8080}"

echo "=== Configuring nginx proxy ==="
echo "BACKEND_URL=$BACKEND_URL"

# Process nginx template - ONLY substitute BACKEND_URL (not nginx vars like $uri)
envsubst '$BACKEND_URL' < /etc/nginx/nginx-template.conf > /etc/nginx/conf.d/default.conf

# Show generated config for debugging
echo "Generated nginx config:"
cat /etc/nginx/conf.d/default.conf
echo "=== Nginx configuration ready ==="
STARTUP

# Make startup script executable
RUN chmod +x /docker-entrypoint.d/10-envsubst-backend.sh

# Set proper ownership (must be done as root before switching user)
RUN chown -R appuser:appuser /usr/share/nginx/html && \
    chown -R appuser:appuser /var/cache/nginx && \
    chown -R appuser:appuser /var/log/nginx && \
    chown -R appuser:appuser /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && \
    chown -R appuser:appuser /var/run/nginx.pid

# Switch to non-root user
USER appuser

# Environment variable for backend URL (set at deploy time)
ENV BACKEND_URL=http://localhost:8080

# Expose port 8080 (Cloud Run default)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Start Nginx (docker-entrypoint.d scripts run automatically)
CMD ["nginx", "-g", "daemon off;"]
