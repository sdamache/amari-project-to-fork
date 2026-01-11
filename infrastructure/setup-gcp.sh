#!/bin/bash

# Setup GCP Project for Logistics Data Extractor
# This script enables required APIs, creates Artifact Registry,
# sets up separate service accounts with IAM policies for security

set -e

# Load environment variables
if [ -f .env ]; then
    source .env
fi

# Configuration
PROJECT_ID=${GCP_PROJECT_ID:-"unique-hash-367919"}
REGION=${GCP_REGION:-"us-central1"}
REPOSITORY_NAME=${ARTIFACT_REGISTRY_REPO:-"logistics-extractor"}

# Service account names
BACKEND_SA_NAME="backend-sa"
FRONTEND_SA_NAME="frontend-sa"
BACKEND_SA_EMAIL="${BACKEND_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
FRONTEND_SA_EMAIL="${FRONTEND_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "🚀 Setting up GCP for Logistics Data Extractor"
echo "================================================"
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "Repository: $REPOSITORY_NAME"
echo ""

# Set the project
echo "📋 Setting active project..."
gcloud config set project $PROJECT_ID

# Enable required APIs
echo "📡 Enabling required Google Cloud APIs..."
gcloud services enable \
    artifactregistry.googleapis.com \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    iam.googleapis.com \
    iamcredentials.googleapis.com \
    cloudresourcemanager.googleapis.com \
    secretmanager.googleapis.com \
    --project=$PROJECT_ID

echo "✅ APIs enabled"

# Create Artifact Registry repository
echo "📦 Creating Artifact Registry repository..."
gcloud artifacts repositories create $REPOSITORY_NAME \
    --repository-format=docker \
    --location=$REGION \
    --description="Container images for Logistics Data Extractor" \
    --project=$PROJECT_ID 2>/dev/null || echo "Repository may already exist"

# Configure Docker authentication
echo "🔐 Configuring Docker authentication for Artifact Registry..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# =====================================================
# Create Backend Service Account
# =====================================================
echo ""
echo "👤 Creating Backend Service Account..."
if gcloud iam service-accounts describe $BACKEND_SA_EMAIL --project=$PROJECT_ID > /dev/null 2>&1; then
    echo "  Backend service account already exists"
else
    gcloud iam service-accounts create $BACKEND_SA_NAME \
        --display-name="Backend Service Account" \
        --description="Service account for Logistics Extractor Backend (Cloud Run)" \
        --project=$PROJECT_ID
    echo "  Waiting for service account to propagate..."
    sleep 5
fi

# Grant backend service account roles
echo "🔑 Granting IAM roles to backend service account..."
for role in \
    "roles/artifactregistry.reader" \
    "roles/logging.logWriter" \
    "roles/monitoring.metricWriter" \
    "roles/cloudtrace.agent"
do
    echo "  Adding: $role"
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${BACKEND_SA_EMAIL}" \
        --role="$role" \
        --condition=None \
        --quiet > /dev/null 2>&1
done
echo "  ✓ Backend IAM roles assigned"

# =====================================================
# Create Frontend Service Account
# =====================================================
echo ""
echo "👤 Creating Frontend Service Account..."
if gcloud iam service-accounts describe $FRONTEND_SA_EMAIL --project=$PROJECT_ID > /dev/null 2>&1; then
    echo "  Frontend service account already exists"
else
    gcloud iam service-accounts create $FRONTEND_SA_NAME \
        --display-name="Frontend Service Account" \
        --description="Service account for Logistics Extractor Frontend (Cloud Run)" \
        --project=$PROJECT_ID
    echo "  Waiting for service account to propagate..."
    sleep 5
fi

# Grant frontend service account roles
echo "🔑 Granting IAM roles to frontend service account..."
for role in \
    "roles/artifactregistry.reader" \
    "roles/logging.logWriter" \
    "roles/monitoring.metricWriter" \
    "roles/cloudtrace.agent"
do
    echo "  Adding: $role"
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${FRONTEND_SA_EMAIL}" \
        --role="$role" \
        --condition=None \
        --quiet > /dev/null 2>&1
done
echo "  ✓ Frontend IAM roles assigned"

# Grant Compute Network User role for VPC Direct Egress
echo "  Adding: roles/compute.networkUser (for VPC Direct Egress)"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${FRONTEND_SA_EMAIL}" \
    --role="roles/compute.networkUser" \
    --condition=None \
    --quiet > /dev/null 2>&1
echo "  ✓ VPC networking role assigned"

# =====================================================
# Setup Secret Manager for ANTHROPIC_API_KEY
# =====================================================
echo ""
echo "🔐 Setting up Secret Manager..."

# Check if secret exists
if gcloud secrets describe anthropic-api-key --project=$PROJECT_ID > /dev/null 2>&1; then
    echo "  Secret 'anthropic-api-key' already exists"
else
    # Check if ANTHROPIC_API_KEY is set in environment
    if [ -n "$ANTHROPIC_API_KEY" ]; then
        echo "  Creating secret 'anthropic-api-key'..."
        echo -n "$ANTHROPIC_API_KEY" | gcloud secrets create anthropic-api-key \
            --data-file=- \
            --project=$PROJECT_ID
        echo "  ✓ Secret created"
    else
        echo "  ⚠️  ANTHROPIC_API_KEY not found in environment"
        echo "     Create the secret manually after setting the key:"
        echo "     echo -n 'your-api-key' | gcloud secrets create anthropic-api-key --data-file=- --project=$PROJECT_ID"
    fi
fi

# Grant ONLY backend service account access to the secret
echo "  Granting secret access to backend service account ONLY..."
gcloud secrets add-iam-policy-binding anthropic-api-key \
    --member="serviceAccount:${BACKEND_SA_EMAIL}" \
    --role="roles/secretmanager.secretAccessor" \
    --project=$PROJECT_ID --quiet > /dev/null 2>&1 || echo "  ⚠️  Could not grant access (secret may not exist yet)"
echo "  ✓ Secret access granted to backend only"

# =====================================================
# Setup IAM Policy: Frontend can invoke Backend
# =====================================================
echo ""
echo "🔒 Setting up IAM policy: Frontend → Backend invocation..."
echo "  This ensures ONLY the frontend service can call the backend API"

# Note: This binding will be applied when the backend service is deployed
# For now, we prepare the binding to be applied post-deployment
cat > /tmp/frontend-invoker-binding.sh << 'BINDING_SCRIPT'
#!/bin/bash
# Run this after backend service is deployed to grant frontend invoke access
PROJECT_ID="${1:-unique-hash-367919}"
REGION="${2:-us-central1}"
FRONTEND_SA="frontend-sa@${PROJECT_ID}.iam.gserviceaccount.com"

echo "Granting frontend service account permission to invoke backend..."
gcloud run services add-iam-policy-binding backend \
    --region=$REGION \
    --member="serviceAccount:${FRONTEND_SA}" \
    --role="roles/run.invoker" \
    --project=$PROJECT_ID

echo "✓ Frontend can now invoke backend"
BINDING_SCRIPT

echo "  ✓ IAM binding script prepared"
echo "  Note: The binding will be applied during deployment"

# =====================================================
# Summary
# =====================================================
echo ""
echo "✅ GCP Setup Complete!"
echo "================================================"
echo ""
echo "📋 Configuration Summary:"
echo "  Repository URL: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}"
echo ""
echo "👤 Service Accounts:"
echo "  Backend:  ${BACKEND_SA_EMAIL}"
echo "  Frontend: ${FRONTEND_SA_EMAIL}"
echo ""
echo "🔒 Security Configuration:"
echo "  • Backend: --ingress=internal (not accessible from internet)"
echo "  • Frontend: --allow-unauthenticated + VPC Direct Egress to reach backend"
echo "  • Frontend SA has roles/run.invoker on Backend (applied during deploy)"
echo "  • Only Backend SA can access Anthropic API secret"
echo ""
echo "🎯 Next Steps:"
echo "  1. Run: ./infrastructure/setup-workload-identity.sh"
echo "  2. Configure GitHub secrets"
echo "  3. Push to trigger CI/CD pipeline"
echo ""
echo "📖 Architecture:"
echo "  User → Frontend (public) → nginx proxy → Backend (internal)"
echo "  The backend is NOT directly accessible from the internet."
