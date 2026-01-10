import pytest
import os
import sys
from datetime import date
from pathlib import Path
import difflib

# Add backend to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app.services.extractor import extract_data
from app.utils.excel_parser import parse_excel
from app.utils.image_converter import convert_pdf_to_images
from app.schemas import ShipmentResponse

# Define paths
ROOT_DIR = Path(__file__).resolve().parent.parent.parent
PDF_PATH = ROOT_DIR / 'BL-COSU534343282.pdf'
EXCEL_PATH = ROOT_DIR / 'Demo-Invoice-PackingList_1.xlsx'

# Configuration
ADDRESS_MATCH_THRESHOLD = 0.8
FLOAT_TOLERANCE = 0.01

# Ground Truth
GROUND_TRUTH = {
    "bill_of_lading_number": "ZMLU34110002",
    "container_number": "MSCU1234567",
    "consignee_name": "KABOFER TRADING INC",
    "consignee_address": "66-89 MAIN ST 8GH 643 FLUSHING, NY, 94089 US",
    "date_of_export": date(2019, 8, 22),
    "line_items_count": 18,
    "total_gross_weight": 16250.0,
    "total_invoice_amount": 23211.24,
    "average_gross_weight": 902.7778,
    "average_price": 1289.5133
}

def normalize_text(text: str) -> str:
    """Lowercase and remove extra whitespace."""
    if not text:
        return ""
    return " ".join(text.lower().split())

def check_fuzzy_match(extracted: str, expected: str) -> bool:
    norm_ext = normalize_text(extracted)
    norm_exp = normalize_text(expected)
    ratio = difflib.SequenceMatcher(None, norm_ext, norm_exp).ratio()
    return ratio >= ADDRESS_MATCH_THRESHOLD

@pytest.fixture
def file_content():
    if not PDF_PATH.exists() or not EXCEL_PATH.exists():
        pytest.skip("Test files not found in repository root")
    
    with open(PDF_PATH, 'rb') as f:
        pdf_bytes = f.read()
    with open(EXCEL_PATH, 'rb') as f:
        excel_bytes = f.read()
        
    return pdf_bytes, excel_bytes

def test_excel_parsing_unit(file_content):
    _, excel_bytes = file_content
    markdown = parse_excel(excel_bytes)
    assert markdown is not None
    assert len(markdown) > 0
    assert "Description" in markdown or "Weight" in markdown

def test_pdf_conversion_unit(file_content):
    pdf_bytes, _ = file_content
    images = convert_pdf_to_images(pdf_bytes, max_pages=1)
    assert len(images) > 0
    assert isinstance(images[0], str) # base64 string

@pytest.mark.skipif(not os.getenv("ANTHROPIC_API_KEY"), reason="ANTHROPIC_API_KEY not set")
def test_end_to_end_extraction(file_content):
    pdf_bytes, excel_bytes = file_content
    
    # 1. Preprocess
    images = convert_pdf_to_images(pdf_bytes)
    excel_markdown = parse_excel(excel_bytes)
    
    # 2. Extract
    extracted_data = extract_data(images, excel_markdown)
    
    # 3. Calculate Averages (Backend Logic)
    avg_gross_weight = None
    if extracted_data.total_gross_weight and extracted_data.line_items_count:
            avg_gross_weight = extracted_data.total_gross_weight / extracted_data.line_items_count
            
    avg_price = None
    if extracted_data.total_invoice_amount and extracted_data.line_items_count:
        avg_price = extracted_data.total_invoice_amount / extracted_data.line_items_count

    data_dict = extracted_data.model_dump()
    data_dict['average_gross_weight'] = avg_gross_weight
    data_dict['average_price'] = avg_price
    
    # 4. Assertions
    
    # Strings (Exact)
    assert normalize_text(data_dict['bill_of_lading_number']) == normalize_text(GROUND_TRUTH['bill_of_lading_number'])
    assert normalize_text(data_dict['container_number']) == normalize_text(GROUND_TRUTH['container_number'])
    assert normalize_text(data_dict['consignee_name']) == normalize_text(GROUND_TRUTH['consignee_name'])
    
    # Address (Fuzzy)
    assert check_fuzzy_match(data_dict['consignee_address'], GROUND_TRUTH['consignee_address']), \
        f"Address mismatch: Got '{data_dict['consignee_address']}', expected '{GROUND_TRUTH['consignee_address']}'"
        
    # Date
    assert data_dict['date_of_export'] == GROUND_TRUTH['date_of_export']
    
    # Integers
    assert data_dict['line_items_count'] == GROUND_TRUTH['line_items_count']
    
    # Floats
    assert abs(data_dict['total_gross_weight'] - GROUND_TRUTH['total_gross_weight']) < FLOAT_TOLERANCE
    assert abs(data_dict['total_invoice_amount'] - GROUND_TRUTH['total_invoice_amount']) < FLOAT_TOLERANCE
    assert abs(data_dict['average_gross_weight'] - GROUND_TRUTH['average_gross_weight']) < FLOAT_TOLERANCE
    assert abs(data_dict['average_price'] - GROUND_TRUTH['average_price']) < FLOAT_TOLERANCE
