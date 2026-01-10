from openai import OpenAI
from app.core.config import settings

client = OpenAI(api_key="")


def extract_field_from_document(document_text):
    """
    Use LLM to extract specific field from document text.
    
    Args:
        document_text: Text from the document
        
    Returns:
        str: Extracted field value
    """

    prompt = f"Extract the data from the following documents:\n\n{document_text}"

    response = client.completions.create(model="text-davinci-003",
                                         prompt=prompt,
                                         max_tokens=100,
                                         temperature=1)
    return response.choices[0].text.strip()
