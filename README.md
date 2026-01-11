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

## Production Engineering

### Cloud Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          PUBLIC INTERNET                             │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │      Frontend           │
                    │    (Public Ingress)     │
                    │      Cloud Run          │
                    │   VPC Egress Enabled    │
                    └────────────┬────────────┘
                                 │
              ┌──────────────────┴──────────────────┐
              │           VPC Network               │
              │    (Private Google Access)          │
              │                                     │
              │  ┌─────────────────────────────┐    │
              │  │        Backend              │    │
              │  │   (Internal Ingress Only)   │    │
              │  │        Cloud Run            │    │
              │  └─────────────────────────────┘    │
              └─────────────────────────────────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
  ┌──────▼──────────┐    ┌───────▼─────────┐    ┌────────▼────────┐
  │ Secret Manager  │    │    Artifact     │    │ Cloud Monitoring│
  │ (API Keys)      │    │    Registry     │    │ Logging, Alerts │
  └─────────────────┘    └─────────────────┘    └─────────────────┘
```

**Traffic Flow:** User → Frontend (public) → VPC Egress → Backend (internal only)

**Security Model:**
- Backend has `--ingress=internal` - not accessible from public internet
- Frontend uses VPC Direct Egress to reach backend securely
- Separate service accounts with minimal IAM permissions
- Secrets stored in Google Secret Manager

### Alerting Strategy

Three alert policies configured with actionable thresholds:

| Alert | Condition | Threshold | Duration |
|-------|-----------|-----------|----------|
| **Service Unavailable** (CRITICAL) | Uptime check fails | 2+ consecutive failures | 2 min |
| **High Error Rate** | 5xx error rate | > 5% of requests | 5 min |
| **High Latency** | P95 response time | > 10 seconds | 5 min |

**Uptime Checks:**
- Both services checked every 60 seconds
- 10-second timeout per check
- Endpoints: `/health` on frontend and backend

**Notification:**
- Email alerts (configurable via `NOTIFICATION_EMAIL`)
- Integrates with Cloud Monitoring notification channels

**Dashboard Widgets (6):**
- Request count by service
- Error rate (5xx) with 0.1/sec threshold
- Latency percentiles (P50, P95, P99) with 10s threshold
- Instance count (auto-scaling visualization)
- Memory utilization (80% yellow, 95% red)
- CPU utilization (80% yellow, 95% red)

### Prometheus Metrics

Custom application metrics exposed at `/metrics`:

| Metric | Type | Labels | Purpose |
|--------|------|--------|---------|
| `document_processing_total` | Counter | `status` | Documents processed (success/error) |
| `llm_extraction_duration_seconds` | Histogram | - | LLM extraction latency |
| `llm_errors_total` | Counter | `provider`, `error_type` | LLM API errors (rate_limit, timeout, api_error) |
| `app_errors_total` | Counter | `endpoint`, `error_type` | Application exceptions |
| `http_requests_total` | Counter | `handler`, `method`, `status` | HTTP request count (auto-instrumented) |
| `http_request_duration_seconds` | Histogram | `handler` | HTTP latency (auto-instrumented) |

### Rollback Strategy

**Automatic Rollback (during deployment):**
- Triggers on health check failure
- Identifies healthy revision from current traffic (guaranteed working)
- Falls back to most recent revision with `status=True`
- Traffic switch is atomic (<5 seconds)

**Manual Rollback (GitHub Actions workflow):**
```bash
# Via GitHub Actions UI:
# 1. Go to Actions → "CD - Rollback Cloud Run Service"
# 2. Click "Run workflow"
# 3. Select: service (backend/frontend/both), revision (optional), reason
```

**Blast Radius:**
| Service | Impact | Recovery Time |
|---------|--------|---------------|
| Backend | HIGH - All API calls affected | <5 seconds |
| Frontend | MEDIUM - UI down, API works | <5 seconds |
| Both | CRITICAL - Complete outage | <5 seconds |

**Revision Retention:** All previous revisions kept for instant rollback.

### Quick Operations

```bash
# Health check all services
./infrastructure/monitoring/monitor-services.sh status

# View recent logs
./infrastructure/monitoring/monitor-services.sh logs backend

# View errors across services
./infrastructure/monitoring/monitor-services.sh errors

# Manual rollback via CLI
gcloud run services update-traffic backend \
  --to-revisions=REVISION_NAME=100 \
  --region=us-central1
```

---

## Assumptions & Decisions

### Application Design

1.  **Vision vs. Text for PDF**: We chose Vision (converting PDF to Images) because Bill of Lading documents often have complex layouts that confuse standard text extractors (pypdf).
2.  **Excel to Markdown**: LLMs understand Markdown tables exceptionally well. Converting Excel to Markdown explicitly preserves the row/column structure better than raw JSON dumps for reasoning tasks.
3.  **Calculated Fields**: We intentionally calculate "Averages" in the backend code (post-LLM) rather than asking the LLM to do math, to eliminate hallucination risks for simple arithmetic.

### Production Deployment

| Decision | Rationale |
|----------|-----------|
| **Internal Ingress for Backend** | Reduces attack surface (1 public endpoint vs 2). Backend has API keys and business logic - shouldn't be directly accessible. |
| **VPC Direct Egress** | Native Cloud Run feature, cheaper than Cloud NAT, no additional infrastructure required. |
| **10-Second Latency Threshold** | LLM extraction takes 3-7s typically. Alert only fires beyond normal expected behavior. |
| **1GB Backend, 512MB Frontend** | Backend handles PDF images + Claude SDK. Frontend is lightweight React SPA with nginx. |
| **Min-Instances=0** | Cost optimization for sporadic usage. Cold start (1-2s) acceptable since extraction waits 5-10s anyway. |
| **Separate Service Accounts** | Principle of least privilege. Backend reads secrets, frontend invokes backend. |
| **5% Error Rate Threshold** | Allows intermittent LLM API timeouts. Alerts on sustained problems, not blips. |
| **2-Minute Availability Window** | Prevents alert fatigue from transient failures during deployments. |

---

## Key Tradeoffs & Future Improvements

### Current Tradeoffs

1.  **Cost of Vision API vs. Local OCR**:
    *   **Current Approach**: Sending high-resolution images of documents to Claude is token-intensive and incurs higher costs. However, it provides superior accuracy for complex layouts (like Bills of Lading) compared to standard text extraction.
    *   **Optimization**: If cost becomes a constraint at scale, we could switch to running a local OCR (e.g., Tesseract or PaddleOCR) to extract text and layout coordinates. We would then pass only the text representation to a cheaper text-based LLM, significantly reducing token usage.

2.  **Latency vs. Experience**:
    *   **Current**: Synchronous extraction, 5-10 second wait.
    *   **Optimization**: Background worker queue (Celery/Redis) + WebSocket notifications.

3.  **All-or-Nothing Deployment**:
    *   **Current**: Full traffic switch on deploy.
    *   **Optimization**: Canary deployments (10% → 50% → 100%) with automatic rollback.

### Production Improvements Roadmap

**Phase 1: Deployment Robustness**
- [ ] Canary deployments (10% traffic for 5 min before full rollout)
- [ ] Enhanced health checks (verify full extraction pipeline, not just HTTP 200)
- [ ] Synthetic monitoring (periodic test extractions to catch silent failures)

**Phase 2: Cost Optimization**
- [ ] Intelligent page selection (extract only needed PDF pages)
- [ ] Extraction caching (Redis for duplicate document detection)
- [ ] Model fallback (Haiku first, Sonnet if low confidence)

**Phase 3: High Availability**
- [ ] Multi-region deployment (us-central1, europe-west1, asia-southeast1)
- [ ] Cross-region failover with Cloud CDN
- [ ] Disaster recovery plan (30-day backups, incident runbooks)

**Phase 4: Observability**
- [ ] Distributed tracing (OpenTelemetry)
- [ ] Custom business metrics (extraction success rate, model accuracy)
- [ ] Cost tracking dashboard (Vision API + LLM spend visibility)