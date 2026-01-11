#!/bin/bash

# Setup Workload Identity Federation for GitHub Actions
# This enables keyless authentication from GitHub to GCP

set -e

# Load environment variables
if [ -f .env ]; then
    source .env
fi

# Configuration
PROJECT_ID=${GCP_PROJECT_ID:-"unique-hash-367919"}
GITHUB_ORG="sdamache"
GITHUB_REPO="amari-project-to-fork"
POOL_NAME="github-actions-pool"
PROVIDER_NAME="github-provider"
SERVICE_ACCOUNT_NAME="github-actions-sa"

echo "🔐 Setting up Workload Identity Federation"
echo "==========================================="
echo "Project ID: $PROJECT_ID"
echo "GitHub Repo: $GITHUB_ORG/$GITHUB_REPO"
echo ""

# Get project number
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
echo "Project Number: $PROJECT_NUMBER"

# Create Workload Identity Pool
echo "🏊 Creating Workload Identity Pool..."
gcloud iam workload-identity-pools create $POOL_NAME \
    --location="global" \
    --display-name="GitHub Actions Pool" \
    --description="Pool for GitHub Actions CI/CD" \
    --project=$PROJECT_ID 2>/dev/null || echo "Pool may already exist"

# Create Workload Identity Provider
echo "🔗 Creating Workload Identity Provider..."
gcloud iam workload-identity-pools providers create-oidc $PROVIDER_NAME \
    --location="global" \
    --workload-identity-pool=$POOL_NAME \
    --display-name="GitHub Provider" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
    --attribute-condition="assertion.repository_owner == '${GITHUB_ORG}'" \
    --project=$PROJECT_ID 2>/dev/null || echo "Provider may already exist"

# Create service account for GitHub Actions
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "👤 Creating service account for GitHub Actions..."
gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
    --display-name="GitHub Actions Service Account" \
    --description="Service account for GitHub Actions deployments" \
    --project=$PROJECT_ID 2>/dev/null || echo "Service account may already exist"

# Grant roles to the service account
echo "🔑 Granting IAM roles to GitHub Actions service account..."
for role in \
    "roles/run.admin" \
    "roles/iam.serviceAccountUser" \
    "roles/artifactregistry.writer" \
    "roles/storage.admin"
do
    echo "  Adding: $role"
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
        --role="$role" \
        --condition=None \
        --quiet > /dev/null 2>&1
done
echo "  ✓ IAM roles assigned"

# Allow GitHub Actions to impersonate the service account
echo "🎭 Configuring workload identity binding..."
gcloud iam service-accounts add-iam-policy-binding $SERVICE_ACCOUNT_EMAIL \
    --project=$PROJECT_ID \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}"

# Output the values needed for GitHub Actions
WORKLOAD_IDENTITY_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/providers/${PROVIDER_NAME}"

echo ""
echo "✅ Workload Identity Federation Setup Complete!"
echo "================================================"
echo ""
echo "📋 Add these to your GitHub repository secrets/variables:"
echo ""
echo "Secrets:"
echo "  (none - using keyless auth!)"
echo ""
echo "Variables:"
echo "  GCP_PROJECT_ID: $PROJECT_ID"
echo "  GCP_REGION: us-central1"
echo "  GCP_SERVICE_ACCOUNT: $SERVICE_ACCOUNT_EMAIL"
echo "  GCP_WORKLOAD_IDENTITY_PROVIDER: $WORKLOAD_IDENTITY_PROVIDER"
echo ""
echo "🎯 Example GitHub Actions usage:"
echo ""
cat << 'EOF'
- name: Authenticate to Google Cloud
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}
    service_account: ${{ vars.GCP_SERVICE_ACCOUNT }}
EOF
