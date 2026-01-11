import time
import instructor
from anthropic import Anthropic, RateLimitError, APITimeoutError, APIError
from app.core.config import settings
from app.schemas import ShipmentExtraction
from app.prompts import SYSTEM_PROMPT, USER_PROMPT_TEMPLATE
from app.metrics import (
    document_processing_total,
    llm_extraction_duration_seconds,
    llm_errors_total,
)
from app.logging_config import get_logger
from typing import List

logger = get_logger(__name__)

# Initialize the client with instructor
# Note: We need to ensure ANTHROPIC_API_KEY is set in the environment or .env file
if not settings.ANTHROPIC_API_KEY:
    logger.warning("ANTHROPIC_API_KEY is not set.")

client = instructor.from_anthropic(Anthropic(api_key=settings.ANTHROPIC_API_KEY))

def extract_data(pdf_images: List[str], excel_text: str) -> ShipmentExtraction:
    """
    Extracts shipment data using Claude 3.5 Sonnet via Instructor.
    
    Args:
        pdf_images: List of base64 encoded strings of the PDF pages.
        excel_text: Markdown string content of the Excel file.
        
    Returns:
        ShipmentExtraction: The extracted structured data.
    """
    
    # Construct the user message content
    # We need to format the content as a list of dictionaries for Claude Vision
    
    content_blocks = []
    
    # Add images
    for img_base64 in pdf_images:
        content_blocks.append({
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": "image/jpeg",
                "data": img_base64
            }
        })
        
    # Add text prompt
    text_content = USER_PROMPT_TEMPLATE.format(excel_text=excel_text)
    content_blocks.append({
        "type": "text",
        "text": text_content
    })

    start_time = time.time()
    try:
        resp = client.messages.create(
            model="claude-sonnet-4-5",
            max_tokens=2048,
            system=SYSTEM_PROMPT,
            messages=[
                {
                    "role": "user",
                    "content": content_blocks
                }
            ],
            response_model=ShipmentExtraction,
        )
        # Record successful extraction metrics
        duration = time.time() - start_time
        llm_extraction_duration_seconds.observe(duration)
        document_processing_total.labels(status="success").inc()
        logger.info(
            f"LLM extraction completed successfully",
            extra={"extra_fields": {"duration_seconds": duration}},
        )
        return resp

    except RateLimitError as e:
        # Rate limit hit - track and re-raise
        duration = time.time() - start_time
        llm_extraction_duration_seconds.observe(duration)
        document_processing_total.labels(status="error").inc()
        llm_errors_total.labels(provider="anthropic", error_type="rate_limit").inc()
        logger.error(
            f"LLM rate limit exceeded",
            extra={"extra_fields": {"duration_seconds": duration, "error": str(e)}},
        )
        raise RuntimeError(f"LLM rate limit exceeded: {str(e)}")

    except APITimeoutError as e:
        # Timeout - track and re-raise
        duration = time.time() - start_time
        llm_extraction_duration_seconds.observe(duration)
        document_processing_total.labels(status="error").inc()
        llm_errors_total.labels(provider="anthropic", error_type="timeout").inc()
        logger.error(
            f"LLM API timeout",
            extra={"extra_fields": {"duration_seconds": duration, "error": str(e)}},
        )
        raise RuntimeError(f"LLM API timeout: {str(e)}")

    except APIError as e:
        # General API error - track and re-raise
        duration = time.time() - start_time
        llm_extraction_duration_seconds.observe(duration)
        document_processing_total.labels(status="error").inc()
        llm_errors_total.labels(provider="anthropic", error_type="api_error").inc()
        logger.error(
            f"LLM API error",
            extra={"extra_fields": {"duration_seconds": duration, "error": str(e)}},
        )
        raise RuntimeError(f"LLM API error: {str(e)}")

    except Exception as e:
        # Record failed extraction metrics for any other error
        duration = time.time() - start_time
        llm_extraction_duration_seconds.observe(duration)
        document_processing_total.labels(status="error").inc()
        llm_errors_total.labels(provider="anthropic", error_type="unknown").inc()
        logger.error(
            f"LLM extraction failed",
            extra={"extra_fields": {"duration_seconds": duration, "error": str(e)}},
            exc_info=True,
        )
        raise RuntimeError(f"LLM Extraction failed: {str(e)}")
