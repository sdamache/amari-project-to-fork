# Multi-stage Dockerfile for Backend Service
# Optimized for Cloud Run deployment

# Stage 1: Build dependencies
FROM python:3.12-slim AS builder

# Install system dependencies for building
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Enable bytecode compilation for faster startup (important for Cloud Run cold starts)
ENV UV_COMPILE_BYTECODE=1

# Copy requirements first for better caching
COPY pyproject.toml uv.lock ./

# Install uv and dependencies
RUN pip install --no-cache-dir uv && \
    uv sync --frozen --no-dev --no-install-project

# Copy the rest of the application code
COPY . .

# Install the project package
RUN uv sync --frozen --no-dev

# Stage 2: Runtime image
FROM python:3.12-slim

# Install runtime dependencies (poppler-utils for pdf2image)
RUN apt-get update && apt-get install -y \
    poppler-utils \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash appuser

# Set working directory
WORKDIR /app

# Copy virtual environment from builder stage
COPY --from=builder /app/.venv /app/.venv

# Copy application code
COPY --from=builder /app/app ./app

# Create data directory for persistence
RUN mkdir -p /app/data && chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Add virtual environment to PATH
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONPATH=/app

# Environment variables for Cloud Run
ENV PORT=8080
ENV HOST=0.0.0.0

# Expose port (Cloud Run uses 8080 by default)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

# Run the FastAPI app
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
