# Logistics Data Extractor

A production-ready full-stack application designed to automate the extraction of shipment data from unstructured documents (Bills of Lading) and structured files (Excel Packing Lists/Invoices). It provides a human-in-the-loop interface for auditing, editing, and persisting the extracted data.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Python](https://img.shields.io/badge/python-3.12-blue.svg)
![React](https://img.shields.io/badge/react-18-blue.svg)
![Docker](https://img.shields.io/badge/docker-enabled-blue.svg)

## Key Features

*   **Multi-Modal Data Extraction**: Seamlessly processes PDF documents (using Vision capabilities) and Excel files (using structural parsing) simultaneously.
*   **AI-Powered Intelligence**: Leverages **Claude 4.5 Sonnet** via the `instructor` library to enforce strict Pydantic schemas, ensuring structured and type-safe output.
*   **Split-Screen Audit UI**: Side-by-side view of the original documents (PDF viewer & Native Excel rendering) and the extracted data form.
*   **Intelligent Calculations**: Automatically computes derived metrics like "Average Gross Weight" and "Average Price" based on extracted totals and line item counts.
*   **Dual Persistence**:
    *   **Local**: Download the finalized data as a JSON file.
    *   **Backend**: Save audited records to the server's filesystem (`backend/data/`).
*   **Robust Evaluation**: Includes a hardcoded evaluation script measuring Accuracy, Precision, Recall, and F1 Score against ground truth data.

---

## Tech Stack

### Backend
*   **Framework**: FastAPI (High-performance Python web framework).
*   **Package Manager**: `uv` (Fast Python package installer and resolver).
*   **LLM Orchestration**: `instructor` + `anthropic` SDK.
*   **Document Processing**:
    *   `pdf2image`: Converts PDF pages to images for Vision analysis (requires `poppler-utils`).
    *   `markitdown` / `pandas`: Converts Excel data to Markdown context for the LLM.

### Frontend
*   **Framework**: React + Vite + TypeScript.
*   **Styling**: Tailwind CSS v4.
*   **State Management**: React Hooks (`useState`, `useEffect`).
*   **Components**:
    *   `react-pdf`: For rendering Bill of Lading PDFs.
    *   `xlsx` (SheetJS): For parsing and rendering Excel previews in-browser.
    *   `react-hook-form`: For managing the editable extraction form.

### Infrastructure
*   **Containerization**: Docker & Docker Compose (Multi-stage builds).
*   **Server**: Nginx (Frontend) + Uvicorn (Backend).
*   **Cloud**: Google Cloud Run (Serverless containers).
*   **CI/CD**: GitHub Actions with Workload Identity Federation.
*   **Monitoring**: Cloud Monitoring, Cloud Logging, Uptime Checks.

---

## Implementation Details

### 1. The Extraction Pipeline (`/process-documents`)
1.  **Input**: User uploads a minimal set of 1 PDF (BOL) and 1 Excel (Invoice/Packing List).
2.  **Preprocessing**:
    *   **PDF**: Converted to a series of images (Vision input). We don't use direct PDF chat using the API to save on the text tokens
    *   **Excel**: Parsed into a clean Markdown table string (Text input).
3.  **LLM Inference**: 
    *   We send both inputs to **Claude 4.5 Sonnet**.
    *   System prompts instruct the model to cross-reference the visual BOL header data with the granular Excel line item data.
    *   We use `instructor` to coerce the output strictly into our `ShipmentExtraction` Pydantic model.
4.  **Post-Processing**:
    *   The backend calculates averages (`total / count`) to ensure mathematical consistency.
    *   Returns a comprehensive `ShipmentResponse` JSON to the frontend.

### 2. The Frontend Experience
*   **Validation**: Prevents submission unless both file types are present.
*   **Visualization**: Custom `DocViewer` component intelligently switches between a PDF canvas and an HTML Table view for Excel files.
*   **Feedback**: "Save" buttons provide visual feedback (Success/Error states) without intrusive alerts.

---

##  Running with Docker (Recommended)

This is the simplest way to run the full stack (Frontend + Backend).

**Prerequisites:**
*   Docker & Docker Compose installed.
*   An Anthropic API Key.

**Steps:**

1.  Set your API Key:
    ```bash
    export ANTHROPIC_API_KEY=your_sk_key_here
    ```

2.  Build and Start:
    ```bash
    docker-compose up --build
    ```

3.  Access the App:
    *   **UI**: Open [http://localhost](http://localhost) in your browser.
    *   **API Docs**: [http://localhost:8080/docs](http://localhost:8080/docs).

---

##  Running Locally

If you prefer to run services individually for development.

### Backend

1.  Navigate to `backend/`:
    ```bash
    cd backend
    ```
2.  Install dependencies using `uv`:
    ```bash
    uv sync
    ```
3.  Run the server:
    ```bash
    export ANTHROPIC_API_KEY=your_key
    uv run uvicorn app.main:app --reload --port 8000
    ```

### Frontend

1.  Navigate to `frontend/`:
    ```bash
    cd frontend
    ```
2.  Install dependencies:
    ```bash
    npm install
    ```
3.  Run the dev server:
    ```bash
    npm run dev
    ```
4.  Open [http://localhost:5173](http://localhost:5173).

---

## Cloud Deployment (GCP Cloud Run)

Deploy to Google Cloud Run with automated CI/CD via GitHub Actions.

### Prerequisites

- GCP Project with billing enabled
- `gcloud` CLI installed and authenticated
- GitHub repository with Actions enabled

### Initial Setup

1. **Configure GCP Infrastructure:**
   ```bash
   # Set your API key in .env
   echo "ANTHROPIC_API_KEY=your_key" >> .env

   # Run GCP setup (creates Artifact Registry, Service Account, Secret Manager)
   ./infrastructure/setup-gcp.sh

   # Setup Workload Identity Federation (keyless auth for GitHub Actions)
   ./infrastructure/setup-workload-identity.sh
   ```

2. **Configure GitHub Variables:**

   The setup scripts will output the values needed. Set them in your GitHub repository:
   ```bash
   gh variable set GCP_PROJECT_ID --body "your-project-id"
   gh variable set GCP_REGION --body "us-central1"
   gh variable set ARTIFACT_REGISTRY_REPO --body "logistics-extractor"
   gh variable set GCP_SERVICE_ACCOUNT --body "github-actions-sa@your-project.iam.gserviceaccount.com"
   gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER --body "projects/PROJECT_NUM/locations/global/workloadIdentityPools/github-actions-pool/providers/github-provider"
   ```

### Automated Deployment (CI/CD)

Push to `main` branch triggers automatic deployment:

```bash
git push origin main
```

The CD workflow will:
1. Build Docker images (linux/amd64)
2. Push to Artifact Registry
3. Deploy backend to Cloud Run
4. Deploy frontend to Cloud Run
5. Update backend CORS with frontend URL

### Manual Deployment

For local deployment without GitHub Actions:

```bash
./infrastructure/deploy-to-cloud-run.sh
```

### Rollback

To rollback to a previous revision:

1. Go to GitHub Actions → "CD - Rollback Cloud Run Service"
2. Click "Run workflow"
3. Select service (backend/frontend/both)
4. Optionally specify a revision name

Or via CLI:
```bash
gcloud run services update-traffic backend --to-revisions=REVISION_NAME=100 --region=us-central1
```

### Monitoring & Logging

Setup monitoring and alerting:
```bash
./infrastructure/monitoring/setup-monitoring.sh
```

Quick monitoring commands:
```bash
# Check service health
./infrastructure/monitoring/monitor-services.sh status

# View backend logs
gcloud run services logs read backend --region=us-central1

# View errors
./infrastructure/monitoring/monitor-services.sh errors
```

View in GCP Console:
- [Cloud Run Dashboard](https://console.cloud.google.com/run)
- [Cloud Monitoring](https://console.cloud.google.com/monitoring)
- [Cloud Logging](https://console.cloud.google.com/logs)

### Service URLs

After deployment:
- **Frontend**: `https://frontend-PROJECT_NUM.us-central1.run.app`
- **Backend**: `https://backend-PROJECT_NUM.us-central1.run.app`
- **API Docs**: `https://backend-PROJECT_NUM.us-central1.run.app/docs`

---

## Evaluation

We have included an evaluation script to verify the extraction quality against a known Ground Truth (the sample files provided in the repo).

**Metrics Calculated:**
*   **Accuracy**: Overall percentage of correctly extracted fields.
*   **Precision**: measure of exactness.
*   **Recall**: measure of completeness.
*   **F1 Score**: Harmonic mean of Precision and Recall.

**To Run Evaluation:**
```bash
cd backend
uv run python evaluation.py
```

**Current Benchmark on the _single sample_ (Claude 4.5 Sonnet):**
*   **Accuracy**: 100.00%
*   **Precision**: 100.00%
*   **Recall**: 100.00%
*   **F1 Score**: 100.00%

---

##  Assumptions & Decisions

1.  **Vision vs. Text for PDF**: We chose Vision (converting PDF to Images) because Bill of Lading documents often have complex layouts that confuse standard text extractors (pypdf).
2.  **Excel to Markdown**: LLMs understand Markdown tables exceptionally well. Converting Excel to Markdown explicitly preserves the row/column structure better than raw JSON dumps for reasoning tasks.
3.  **Calculated Fields**: We intentionally calculate "Averages" in the backend code (post-LLM) rather than asking the LLM to do math, to eliminate hallucination risks for simple arithmetic.

---

## Key Tradeoffs & Future Improvements

1.  **Cost of Vision API vs. Local OCR**:
    *   **Current Approach**: Sending high-resolution images of documents to Claude is token-intensive and incurs higher costs. However, it provides superior accuracy for complex layouts (like Bills of Lading) compared to standard text extraction.
    *   **Optimization**: If cost becomes a constraint at scale, we could switch to running a local OCR (e.g., Tesseract or PaddleOCR) to extract text and layout coordinates. We would then pass only the text representation to a cheaper text-based LLM, significantly reducing token usage.

2.  **Latency vs. Experience**:
    *   **Current Approach**: The extraction is synchronous, leading to a 5-10 second wait time.
    *   **Optimization**: For production loads, offload processing to a background worker queue (Celery/Redis) and use WebSockets to notify the frontend when the extraction is complete.

3.  **Excel Parsing Rigidity**:
    *   **Current Approach**: We rely on converting Excel to Markdown. This works great for standard tables but might struggle with very large or multi-sheet workbooks.
    *   **Optimization**: Implement chunking strategies for large files or use specific header detection heuristics before sending to the LLM.