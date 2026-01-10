import os
from app.utils.pdf_utils import extract_text_from_pdf

def process_documents(file_paths):
    """
    Process different types of documents and extract relevant information.
    
    Args:
        file_paths: List of paths to the documents
        
    Returns:
        dict: Extracted data from documents
    """
    extracted_data = {}
    
    for file_path in file_paths:
        if file_path.endswith(".pdf"):
            extracted_data['pdf_text'] = extract_text_from_pdf(file_path)
    
    
    return extracted_data 