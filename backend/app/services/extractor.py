import time
import instructor
from anthropic import Anthropic
from app.core.config import settings
from app.schemas import ShipmentExtraction
from app.prompts import SYSTEM_PROMPT, USER_PROMPT_TEMPLATE
from app.metrics import document_processing_total, llm_extraction_duration_seconds
from typing import List

# Initialize the client with instructor
# Note: We need to ensure ANTHROPIC_API_KEY is set in the environment or .env file
if not settings.ANTHROPIC_API_KEY:
    print("WARNING: ANTHROPIC_API_KEY is not set.")

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
        return resp
    except Exception as e:
        # Record failed extraction metrics
        duration = time.time() - start_time
        llm_extraction_duration_seconds.observe(duration)
        document_processing_total.labels(status="error").inc()
        # simpler re-raise or logging
        raise RuntimeError(f"LLM Extraction failed: {str(e)}")
