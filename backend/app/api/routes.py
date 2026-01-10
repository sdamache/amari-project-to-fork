from fastapi import APIRouter, UploadFile, File, HTTPException
from typing import List
import os
import json
from datetime import datetime

from app.services.extractor import extract_data
from app.utils.excel_parser import parse_excel
from app.utils.image_converter import convert_pdf_to_images
from app.schemas import ShipmentExtraction, ShipmentResponse

router = APIRouter()

@router.post("/save-shipment")
async def save_shipment_data(data: ShipmentResponse):
    """
    Saves the edited shipment data to the filesystem.
    """
    try:
        # Create data directory if it doesn't exist (though I just created it manually)
        save_dir = "data"
        os.makedirs(save_dir, exist_ok=True)
        
        # Generate filename
        bol_num = data.bill_of_lading_number or "unknown"
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"shipment_{bol_num}_{timestamp}.json"
        file_path = os.path.join(save_dir, filename)
        
        # Save to file
        with open(file_path, "w") as f:
            f.write(data.model_dump_json(indent=2))
            
        return {"message": "Data saved successfully", "filename": filename}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save data: {str(e)}")

@router.post("/process-documents", response_model=ShipmentResponse)
async def extract_shipment_data(
    files: List[UploadFile] = File(...)
):
    """
    Extracts shipment data from uploaded PDF (BOL) and Excel (Packing List/Invoice) files.
    """
    pdf_images = []
    excel_markdown_parts = []
    
    # Analyze files
    for file in files:
        filename = file.filename.lower()
        content = await file.read()
        
        if filename.endswith('.pdf'):
            try:
                # Convert up to 3 pages
                images = convert_pdf_to_images(content, max_pages=3)
                pdf_images.extend(images)
            except Exception as e:
                raise HTTPException(status_code=400, detail=f"Error processing PDF {file.filename}: {str(e)}")
                
        elif filename.endswith('.xlsx') or filename.endswith('.xls'):
            try:
                markdown = parse_excel(content)
                excel_markdown_parts.append(f"File: {file.filename}\n{markdown}")
            except Exception as e:
                raise HTTPException(status_code=400, detail=f"Error processing Excel {file.filename}: {str(e)}")
        
        else:
            # Skip or warn? For now skip unknown types
            continue
            
    # Validation
    if not pdf_images:
        raise HTTPException(status_code=400, detail="No PDF (Bill of Lading) file uploaded.")
    
    if not excel_markdown_parts:
        raise HTTPException(status_code=400, detail="No Excel (Packing List/Invoice) file uploaded.")
    
    full_excel_text = "\n\n".join(excel_markdown_parts)
    
    try:
        extracted_data: ShipmentExtraction = extract_data(pdf_images, full_excel_text)
        
        # Calculate averages
        avg_gross_weight = None
        if extracted_data.total_gross_weight and extracted_data.line_items_count:
             avg_gross_weight = extracted_data.total_gross_weight / extracted_data.line_items_count
             
        avg_price = None
        if extracted_data.total_invoice_amount and extracted_data.line_items_count:
            avg_price = extracted_data.total_invoice_amount / extracted_data.line_items_count
            
        # Construct response
        response = ShipmentResponse(
            **extracted_data.model_dump(),
            average_gross_weight=avg_gross_weight,
            average_price=avg_price
        )
        
        return response
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Extraction failed: {str(e)}")
