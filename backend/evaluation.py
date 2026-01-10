import os
import sys
import dotenv
import difflib
import math
from datetime import date
from typing import Any, Dict, Optional, Tuple

# Load env vars
dotenv.load_dotenv(os.path.join(os.path.dirname(__file__), '.env'))

# Add project root to sys.path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.services.extractor import extract_data
from app.utils.excel_parser import parse_excel
from app.utils.image_converter import convert_pdf_to_images
from app.schemas import ShipmentResponse

# --- CONFIGURATION ---
ADDRESS_MATCH_THRESHOLD = 0.8  # 80% similarity required
FLOAT_TOLERANCE = 0.01         # For float comparisons

# --- GROUND TRUTH DATA ---
# Pre-filled based on the provided sample documents in the repo
GROUND_TRUTH = {
    "bill_of_lading_number": "ZMLU34110002",
    "container_number": "MSCU1234567",
    "consignee_name": "KABOFER TRADING INC",
    "consignee_address": "66-89 MAIN ST 8GH 643 FLUSHING, NY, 94089 US",
    "date_of_export": date(2019, 8, 22),
    "line_items_count": 18,
    "total_gross_weight": 16250.0,
    "total_invoice_amount": 23211.24,
    "average_gross_weight": 902.7778,  # 16250 / 18
    "average_price": 1289.5133         # 23211.24 / 18
}

def normalize_text(text: str) -> str:
    """Lowercase and remove extra whitespace."""
    if not text:
        return ""
    return " ".join(text.lower().split())

def is_match(field: str, extracted: Any, expected: Any) -> Tuple[bool, str]:
    """
    Returns (is_match, reason)
    """
    if extracted is None and expected is None:
        return True, "Both None"
    if extracted is None or expected is None:
        return False, f"One is None: Extracted={extracted}, Expected={expected}"

    # String Fields (Exact Match normalized)
    if field in ["bill_of_lading_number", "container_number", "consignee_name"]:
        norm_ext = normalize_text(str(extracted))
        norm_exp = normalize_text(str(expected))
        if norm_ext == norm_exp:
            return True, "Exact Match"
        return False, f"Mismatch: '{norm_ext}' != '{norm_exp}'"

    # Address (Fuzzy Match)
    if field == "consignee_address":
        norm_ext = normalize_text(str(extracted))
        norm_exp = normalize_text(str(expected))
        ratio = difflib.SequenceMatcher(None, norm_ext, norm_exp).ratio()
        if ratio >= ADDRESS_MATCH_THRESHOLD:
            return True, f"Fuzzy Match ({ratio:.1%})"
        return False, f"Low Similarity ({ratio:.1%}): '{norm_ext}' vs '{norm_exp}'"

    # Date
    if field == "date_of_export":
        if extracted == expected:
            return True, "Date Match"
        return False, f"Date Mismatch: {extracted} != {expected}"

    # Integers
    if field == "line_items_count":
        if extracted == expected:
            return True, "Count Match"
        return False, f"Count Mismatch: {extracted} != {expected}"

    # Floats
    if field in ["total_gross_weight", "total_invoice_amount", "average_gross_weight", "average_price"]:
        try:
            val_ext = float(extracted)
            val_exp = float(expected)
            diff = abs(val_ext - val_exp)
            if diff <= FLOAT_TOLERANCE:
                return True, f"Float Match (Diff: {diff:.4f})"
            return False, f"Float Mismatch: {val_ext} != {val_exp} (Diff: {diff})"
        except ValueError:
            return False, f"Type Error: {extracted} vs {expected}"

    # Fallback
    if extracted == expected:
        return True, "Generic Match"
    return False, f"Generic Mismatch: {extracted} != {expected}"

def calculate_averages(extracted_data):
    # Logic duplicated from routes.py for evaluation
    avg_gross_weight = None
    if extracted_data.total_gross_weight and extracted_data.line_items_count:
            avg_gross_weight = extracted_data.total_gross_weight / extracted_data.line_items_count
            
    avg_price = None
    if extracted_data.total_invoice_amount and extracted_data.line_items_count:
        avg_price = extracted_data.total_invoice_amount / extracted_data.line_items_count
    
    return avg_gross_weight, avg_price

def run_evaluation():
    print("--- 🚀 Starting Evaluation ---")
    
    # 1. Paths
    root_dir = os.path.join(os.path.dirname(__file__), '..')
    pdf_path = os.path.join(root_dir, 'BL-COSU534343282.pdf')
    excel_path = os.path.join(root_dir, 'Demo-Invoice-PackingList_1.xlsx')

    if not os.path.exists(pdf_path) or not os.path.exists(excel_path):
        print("❌ Error: Files not found.")
        return

    # 2. Extract Data
    try:
        print("Processing files...")
        with open(pdf_path, 'rb') as f:
            pdf_bytes = f.read()
        pdf_images = convert_pdf_to_images(pdf_bytes)
        
        with open(excel_path, 'rb') as f:
            excel_bytes = f.read()
            excel_markdown = parse_excel(excel_bytes)
            
        print("Calling LLM...")
        raw_extraction = extract_data(pdf_images, excel_markdown)
        
        # Calculate derived fields to match Response Schema
        avg_weight, avg_price = calculate_averages(raw_extraction)
        
        # Combine into complete dictionary for comparison
        extracted_dict = raw_extraction.model_dump()
        extracted_dict['average_gross_weight'] = avg_weight
        extracted_dict['average_price'] = avg_price

    except Exception as e:
        print(f"❌ Extraction Failed: {e}")
        return

    # 3. Compare
    print("\n--- 📊 Comparison Results ---")
    
    tp = 0  # Matches
    fp = 0  # Extracted value wrong or unexpected
    fn = 0  # Missed (None when expected)
    tn = 0  # Correctly None (not used heavily here as we expect values)

    results_table = []

    for field, expected_val in GROUND_TRUTH.items():
        extracted_val = extracted_dict.get(field)
        match, reason = is_match(field, extracted_val, expected_val)
        
        status = "✅ PASS" if match else "❌ FAIL"
        # Truncate strings for display
        ext_disp = str(extracted_val)[:20] + "..." if len(str(extracted_val)) > 20 else str(extracted_val)
        exp_disp = str(expected_val)[:20] + "..." if len(str(expected_val)) > 20 else str(expected_val)
        
        results_table.append(f"{field:<25} | {ext_disp:<23} | {exp_disp:<23} | {status} ({reason})")

        if match:
            tp += 1
        else:
            if extracted_val is None and expected_val is not None:
                fn += 1
            else:
                fp += 1

    print(f"{'Field':<25} | {'Extracted':<23} | {'Expected':<23} | {'Status'}")
    print("-" * 110)
    for row in results_table:
        print(row)
    print("-" * 110)

    # 4. Metrics
    # Precision = TP / (TP + FP)
    # Recall = TP / (TP + FN)
    # Accuracy = (TP + TN) / Total Fields
    # F1 = 2 * (P * R) / (P + R)

    total_fields = len(GROUND_TRUTH)
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0
    accuracy = (tp + tn) / total_fields
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0

    print("\n--- 📈 Final Metrics ---")
    print(f"Total Fields: {total_fields}")
    print(f"Correct (TP): {tp}")
    print(f"Wrong (FP):   {fp}")
    print(f"Missed (FN):  {fn}")
    print("-" * 20)
    print(f"Accuracy:  {accuracy:.2%}")
    print(f"Precision: {precision:.2%}")
    print(f"Recall:    {recall:.2%}")
    print(f"F1 Score:  {f1:.2%}")

if __name__ == "__main__":
    run_evaluation()