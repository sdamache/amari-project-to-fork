import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.routes import router
import uvicorn

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

app.include_router(router)


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
