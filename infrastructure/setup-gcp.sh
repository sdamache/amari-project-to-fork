#!/bin/bash

# Setup GCP Project for Logistics Data Extractor
# This script enables required APIs and creates Artifact Registry

set -e

# Load environment variables
if [ -f .env ]; then
    source .env
fi

# Configuration
PROJECT_ID=${GCP_PROJECT_ID:-"unique-hash-367919"}
REGION=${GCP_REGION:-"us-central1"}
REPOSITORY_NAME=${ARTIFACT_REGISTRY_REPO:-"logistics-extractor"}

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

# Create service account for Cloud Run
SERVICE_ACCOUNT_NAME="logistics-extractor-sa"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "👤 Creating service account for Cloud Run..."
if gcloud iam service-accounts describe $SERVICE_ACCOUNT_EMAIL --project=$PROJECT_ID > /dev/null 2>&1; then
    echo "  Service account already exists"
else
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
        --display-name="Logistics Extractor Service Account" \
        --description="Service account for Logistics Data Extractor Cloud Run services" \
        --project=$PROJECT_ID
    echo "  Waiting for service account to propagate..."
    sleep 10
fi

# Verify service account exists before proceeding
echo "  Verifying service account..."
gcloud iam service-accounts describe $SERVICE_ACCOUNT_EMAIL --project=$PROJECT_ID > /dev/null 2>&1 || {
    echo "❌ Error: Service account not found. Please try again."
    exit 1
}
echo "  ✓ Service account verified"

# Grant necessary IAM roles to the service account
echo "🔑 Granting IAM roles to service account..."
for role in \
    "roles/artifactregistry.reader" \
    "roles/logging.logWriter" \
    "roles/monitoring.metricWriter" \
    "roles/cloudtrace.agent"
do
    echo "  Adding: $role"
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
        --role="$role" \
        --condition=None \
        --quiet > /dev/null 2>&1
done
echo "  ✓ IAM roles assigned"

echo ""
echo "✅ GCP Setup Complete!"
echo "================================================"
echo ""
echo "📋 Configuration Summary:"
echo "  Repository URL: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}"
echo "  Service Account: ${SERVICE_ACCOUNT_EMAIL}"
echo ""
echo "🎯 Next Steps:"
echo "  1. Run: ./infrastructure/setup-workload-identity.sh"
echo "  2. Configure GitHub secrets"
echo "  3. Push to trigger CI/CD pipeline"
