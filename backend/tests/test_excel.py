import os
import sys

# Add the project root to sys.path so we can import app
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app.utils.excel_parser import parse_excel

def test_excel_parsing():
    # Path to the dummy excel file in the root
    excel_path = os.path.join(os.path.dirname(__file__), '..', '..', 'Demo-Invoice-PackingList_1.xlsx')
    
    if not os.path.exists(excel_path):
        print(f"Error: Test file not found at {excel_path}")
        return

    print(f"Reading {excel_path}...")
    with open(excel_path, 'rb') as f:
        file_bytes = f.read()

    try:
        markdown_output = parse_excel(file_bytes)
        print("\n--- Markdown Output ---\n")
        print(markdown_output)
        print("\n-----------------------\n")
        print("Success: Excel converted to Markdown.")
    except Exception as e:
        print(f"Failed: {e}")

if __name__ == "__main__":
    test_excel_parsing()
