import os
import sys

# Add the project root to sys.path so we can import app
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app.utils.image_converter import convert_pdf_to_images

def test_pdf_conversion():
    # Path to the dummy pdf file in the root
    pdf_path = os.path.join(os.path.dirname(__file__), '..', '..', 'BL-COSU534343282.pdf')
    
    if not os.path.exists(pdf_path):
        print(f"Error: Test file not found at {pdf_path}")
        return

    print(f"Reading {pdf_path}...")
    with open(pdf_path, 'rb') as f:
        file_bytes = f.read()

    try:
        images = convert_pdf_to_images(file_bytes)
        print(f"Success: Converted PDF to {len(images)} images.")
        if len(images) > 0:
            print(f"First image base64 length: {len(images[0])}")
            print(f"Sample start: {images[0][:50]}...")
    except Exception as e:
        print(f"Failed: {e}")

if __name__ == "__main__":
    test_pdf_conversion()
