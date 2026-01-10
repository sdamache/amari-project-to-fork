from pydantic import BaseModel, Field
from typing import Optional
from datetime import date

class ShipmentExtraction(BaseModel):
    """
    Raw data extracted from documents by the LLM.
    """
    bill_of_lading_number: Optional[str] = Field(
        None, description="The Bill of Lading Number, usually found on the top right of the PDF."
    )
    container_number: Optional[str] = Field(
        None, description="The Container Number. If multiple are present, pick the primary one."
    )
    consignee_name: Optional[str] = Field(
        None, description="The Name of the Consignee."
    )
    consignee_address: Optional[str] = Field(
        None, description="The Address of the Consignee."
    )
    date_of_export: Optional[date] = Field(
        None, description="Date of Export/Shipment normalized to YYYY-MM-DD."
    )
    line_items_count: Optional[int] = Field(
        None, description="Count of distinct product rows in the packing list/invoice (excluding headers/footers)."
    )
    total_gross_weight: Optional[float] = Field(
        None, description="The Total Gross Weight of the shipment."
    )
    total_invoice_amount: Optional[float] = Field(
        None, description="The Total Invoice Amount/Value."
    )

class ShipmentResponse(ShipmentExtraction):
    """
    Full response model sent to the frontend, including calculated averages.
    """
    average_gross_weight: Optional[float] = Field(
        None, description="Calculated: Total Gross Weight / Line Items Count"
    )
    average_price: Optional[float] = Field(
        None, description="Calculated: Total Invoice Amount / Line Items Count"
    )

