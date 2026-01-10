import tempfile
import os
from markitdown import MarkItDown

def parse_excel(file_bytes: bytes) -> str:
    """
    Reads Excel file bytes and converts it to a Markdown string using MarkItDown.
    
    Args:
        file_bytes: The raw bytes of the Excel file.
        
    Returns:
        str: A Markdown string representation of the Excel data.
    """
    try:
        # MarkItDown typically works with file paths, so we create a temp file.
        with tempfile.NamedTemporaryFile(suffix=".xlsx", delete=False) as temp_file:
            temp_file.write(file_bytes)
            temp_file_path = temp_file.name

        try:
            md = MarkItDown(enable_plugins=False)
            result = md.convert(temp_file_path)
            return result.text_content
        finally:
            if os.path.exists(temp_file_path):
                os.remove(temp_file_path)
                
    except Exception as e:
        raise ValueError(f"Error processing Excel file with MarkItDown: {str(e)}")


