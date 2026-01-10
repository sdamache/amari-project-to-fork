from pdf2image import convert_from_bytes
import io
import base64
from typing import List

def convert_pdf_to_images(file_bytes: bytes, max_pages: int = 2) -> List[str]:
    """
    Converts a PDF (bytes) into a list of Base64 encoded JPEG strings.
    
    Args:
        file_bytes: The raw bytes of the PDF file.
        max_pages: The maximum number of pages to convert from the start.
        
    Returns:
        List[str]: A list of base64 strings (images), one for each page.
    """
    try:
        # returns sequence of PIL Image objects
        # To avoid index errors if pdf has fewer pages than max_pages, we can catch or let pdf2image handle it (it usually handles it gracefully)
        # However, convert_from_bytes doesn't have a 'max_pages' argument directly, it has first_page and last_page or paths.
        # But we can query page count or just request up to max.
        # simpler: just get all and slice, OR assume 2 pages is small enough.
        # Optimization: use last_page=max_pages
        
        images = convert_from_bytes(file_bytes, first_page=1, last_page=max_pages, fmt="jpeg")
        
        base64_images = []
        for img in images:
            # Save to BytesIO buffer as JPEG
            buffered = io.BytesIO()
            img.save(buffered, format="JPEG")
            img_str = base64.b64encode(buffered.getvalue()).decode("utf-8")
            base64_images.append(img_str)
            
        return base64_images
    except Exception as e:
        raise ValueError(f"Error converting PDF to images: {str(e)}")
