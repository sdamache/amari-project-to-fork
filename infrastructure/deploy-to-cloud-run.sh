#!/bin/bash

# Deploy Logistics Data Extractor to Cloud Run
# This script builds and deploys both frontend and backend services

set -e

# Load environment variables
if [ -f .env ]; then
    source .env
fi

# Configuration
PROJECT_ID=${GCP_PROJECT_ID:-"unique-hash-367919"}
REGION=${GCP_REGION:-"us-central1"}
REPOSITORY_NAME=${ARTIFACT_REGISTRY_REPO:-"logistics-extractor"}
SERVICE_ACCOUNT="logistics-extractor-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# Image configuration
IMAGE_BASE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}"
BUILD_TAG=${BUILD_TAG:-$(date +%Y%m%d-%H%M%S)}

BACKEND_IMAGE="${IMAGE_BASE}/backend:${BUILD_TAG}"
FRONTEND_IMAGE="${IMAGE_BASE}/frontend:${BUILD_TAG}"

echo "🚀 Deploying Logistics Data Extractor to Cloud Run"
echo "==================================================="
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "Build Tag: $BUILD_TAG"
echo ""

# Verify Secret Manager secret exists
echo "🔐 Verifying ANTHROPIC_API_KEY secret in Secret Manager..."
if ! gcloud secrets describe anthropic-api-key --project=$PROJECT_ID > /dev/null 2>&1; then
    echo "❌ Error: anthropic-api-key secret not found in Secret Manager"
    echo "   Run ./infrastructure/setup-gcp.sh to create it"
    exit 1
fi
echo "  ✓ Secret found"

# Configure Docker authentication
echo "🔐 Configuring Docker authentication..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# =====================================================
# Build and Deploy Backend
# =====================================================
echo ""
echo "📦 Building Backend Image (linux/amd64)..."
docker build --platform linux/amd64 -t $BACKEND_IMAGE ./backend

echo "⬆️  Pushing Backend Image..."
docker push $BACKEND_IMAGE

echo "🚀 Deploying Backend to Cloud Run..."
BACKEND_URL=$(gcloud run deploy backend \
    --image=$BACKEND_IMAGE \
    --region=$REGION \
    --platform=managed \
    --service-account=$SERVICE_ACCOUNT \
    --allow-unauthenticated \
    --port=8080 \
    --memory=1Gi \
    --cpu=1 \
    --min-instances=0 \
    --max-instances=10 \
    --timeout=300s \
    --set-secrets="ANTHROPIC_API_KEY=anthropic-api-key:latest" \
    --project=$PROJECT_ID \
    --format="value(status.url)")

echo "✅ Backend deployed: $BACKEND_URL"

# Wait for backend to be healthy
echo "⏳ Waiting for backend health check..."
for i in {1..10}; do
    if curl -sf "${BACKEND_URL}/health" > /dev/null 2>&1; then
        echo "✅ Backend is healthy!"
        break
    fi
    echo "   Attempt $i/10..."
    sleep 5
done

# =====================================================
# Build and Deploy Frontend
# =====================================================
echo ""
echo "📦 Building Frontend Image (linux/amd64)..."
docker build \
    --platform linux/amd64 \
    --build-arg VITE_API_URL=$BACKEND_URL \
    -t $FRONTEND_IMAGE \
    ./frontend

echo "⬆️  Pushing Frontend Image..."
docker push $FRONTEND_IMAGE

echo "🚀 Deploying Frontend to Cloud Run..."
FRONTEND_URL=$(gcloud run deploy frontend \
    --image=$FRONTEND_IMAGE \
    --region=$REGION \
    --platform=managed \
    --service-account=$SERVICE_ACCOUNT \
    --allow-unauthenticated \
    --port=8080 \
    --memory=512Mi \
    --cpu=1 \
    --min-instances=0 \
    --max-instances=5 \
    --timeout=60s \
    --project=$PROJECT_ID \
    --format="value(status.url)")

echo "✅ Frontend deployed: $FRONTEND_URL"

# Update backend CORS with frontend URL
echo ""
echo "🔄 Updating backend CORS settings..."
gcloud run services update backend \
    --region=$REGION \
    --update-env-vars="ALLOWED_ORIGINS=${FRONTEND_URL}" \
    --project=$PROJECT_ID \
    --quiet

# =====================================================
# Summary
# =====================================================
echo ""
echo "🎉 Deployment Complete!"
echo "==================================================="
echo ""
echo "📋 Service URLs:"
echo "  Frontend: $FRONTEND_URL"
echo "  Backend:  $BACKEND_URL"
echo "  API Docs: ${BACKEND_URL}/docs"
echo ""
echo "📦 Container Images:"
echo "  Backend:  $BACKEND_IMAGE"
echo "  Frontend: $FRONTEND_IMAGE"
echo ""
echo "🔧 Useful Commands:"
echo "  View logs:    gcloud run logs read backend --region=$REGION"
echo "  View metrics: https://console.cloud.google.com/run?project=$PROJECT_ID"
echo ""
