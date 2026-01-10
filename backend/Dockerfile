# Use a Python image with uv pre-installed
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

# Install system dependencies (poppler-utils for pdf2image)
RUN apt-get update && apt-get install -y \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Set the working directory to /app
WORKDIR /app

# Enable bytecode compilation
ENV UV_COMPILE_BYTECODE=1

# Copy the lock file and pyproject.toml first to cache dependencies
COPY pyproject.toml uv.lock ./

# Install dependencies using uv
# --frozen: sync exactly from uv.lock
# --no-dev: do not install dev dependencies
# --no-install-project: do not install the project package itself yet
RUN uv sync --frozen --no-dev --no-install-project

# Copy the rest of the application code
COPY . .

# Install the project package itself
RUN uv sync --frozen --no-dev

# Place the virtual environment in the PATH
ENV PATH="/app/.venv/bin:$PATH"

# Create a directory for data persistence
# RUN mkdir -p data

# Expose port 8000
EXPOSE 8000

# Run the FastAPI app using uvicorn
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"] 