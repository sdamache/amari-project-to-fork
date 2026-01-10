import os
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Anthropic API Key
    ANTHROPIC_API_KEY: str = os.getenv("ANTHROPIC_API_KEY", "")
    
    # Document types
    ALLOWED_DOCUMENT_TYPES: list[str] = [".pdf", ".xlsx"]

    class Config:
        env_file = ".env"

settings = Settings()

