import os
import sys
import dotenv

# Load env vars from .env in the root if it exists
dotenv.load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

# Add the project root to sys.path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app.services.extractor import extract_data
from app.utils.excel_parser import parse_excel
from app.utils.image_converter import convert_pdf_to_images

def test_full_extraction():
    # 1. Get files
    root_dir = os.path.join(os.path.dirname(__file__), '..', '..') # Go up two levels to repo root
    pdf_path = os.path.join(root_dir, 'BL-COSU534343282.pdf')
    excel_path = os.path.join(root_dir, 'Demo-Invoice-PackingList_1.xlsx')
    
    if not os.path.exists(pdf_path) or not os.path.exists(excel_path):
        print("Files not found for testing.")
        return

    # 2. Process Excel
    print("Processing Excel...")
    with open(excel_path, 'rb') as f:
        excel_bytes = f.read()
    excel_markdown = parse_excel(excel_bytes)
    
    # 3. Process PDF
    print("Processing PDF...")
    with open(pdf_path, 'rb') as f:
        pdf_bytes = f.read()
    pdf_images = convert_pdf_to_images(pdf_bytes)
    
    # 4. Call LLM
    print("Calling LLM (requires ANTHROPIC_API_KEY)...")
    try:
        data = extract_data(pdf_images, excel_markdown)
        print("\n--- Extracted Data ---")
        print(data.model_dump_json(indent=2))
        print("----------------------")
    except Exception as e:
        print(f"Extraction failed: {e}")

if __name__ == "__main__":
    if not os.getenv("ANTHROPIC_API_KEY"):
        print("Skipping test: ANTHROPIC_API_KEY not found.")
    else:
        test_full_extraction()
