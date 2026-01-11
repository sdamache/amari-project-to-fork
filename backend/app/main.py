import os
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.routes import router
from app.logging_config import setup_logging, RequestLoggingMiddleware, get_logger
import uvicorn

# Configure structured logging for GCP Cloud Logging
log_level = logging.DEBUG if os.getenv("DEBUG", "").lower() == "true" else logging.INFO
setup_logging(
    service_name=os.getenv("SERVICE_NAME", "backend"),
    level=log_level,
    project_id=os.getenv("GCP_PROJECT_ID"),
)
logger = get_logger(__name__)

app = FastAPI(title="Document Processing API")

# Get allowed origins from environment or use defaults
# Cloud Run URLs will be added dynamically
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "").split(",") if os.getenv("ALLOWED_ORIGINS") else []
DEFAULT_ORIGINS = [
    "http://localhost:5173",  # Vite dev server
    "http://localhost:8080",  # Local Docker
    "http://localhost",
    "http://127.0.0.1",
]

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=DEFAULT_ORIGINS + ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Add request logging middleware (must be added after CORS to log actual requests)
app.add_middleware(RequestLoggingMiddleware, logger=logger)

app.include_router(router)


@app.on_event("startup")
async def startup_event():
    """Log service startup."""
    logger.info(
        "Service started",
        extra={"extra_fields": {"event": "startup", "port": os.getenv("PORT", 8080)}},
    )


@app.on_event("shutdown")
async def shutdown_event():
    """Log service shutdown."""
    logger.info("Service shutting down", extra={"extra_fields": {"event": "shutdown"}})


@app.get("/")
async def root():
    return {"message": "Welcome to the Document Processing API"}


@app.get("/health")
async def health_check():
    """Health check endpoint for Cloud Run and load balancers."""
    return {"status": "healthy", "service": "backend"}


if __name__ == "__main__":
    port = int(os.getenv("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port, reload=True)
