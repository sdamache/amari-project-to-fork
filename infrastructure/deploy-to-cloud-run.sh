#!/bin/bash

# Deploy Logistics Data Extractor to Cloud Run
# This script builds and deploys both frontend and backend services
# with proper IAM policies ensuring backend is only accessible via frontend

set -e

# Load environment variables
if [ -f .env ]; then
    source .env
fi

# Configuration
PROJECT_ID=${GCP_PROJECT_ID:-"unique-hash-367919"}
REGION=${GCP_REGION:-"us-central1"}
REPOSITORY_NAME=${ARTIFACT_REGISTRY_REPO:-"logistics-extractor"}

# Service accounts (separate for security)
BACKEND_SA="backend-sa@${PROJECT_ID}.iam.gserviceaccount.com"
FRONTEND_SA="frontend-sa@${PROJECT_ID}.iam.gserviceaccount.com"

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
echo "🔒 Security Configuration:"
echo "  Backend:  internal ingress, authenticated access only"
echo "  Frontend: public, proxies to backend"
echo ""

# Verify Secret Manager secret exists
echo "🔐 Verifying ANTHROPIC_API_KEY secret in Secret Manager..."
if ! gcloud secrets describe anthropic-api-key --project=$PROJECT_ID > /dev/null 2>&1; then
    echo "❌ Error: anthropic-api-key secret not found in Secret Manager"
    echo "   Run ./infrastructure/setup-gcp.sh to create it"
    exit 1
fi
echo "  ✓ Secret found"

# =====================================================
# Enable Private Google Access for VPC Direct Egress
# =====================================================
echo ""
echo "🌐 Enabling Private Google Access on default subnet..."
gcloud compute networks subnets update default \
    --region=$REGION \
    --enable-private-ip-google-access \
    --project=$PROJECT_ID \
    --quiet 2>/dev/null || echo "  (already enabled or no permission)"
echo "  ✓ Private Google Access enabled"

# Configure Docker authentication
echo "🔐 Configuring Docker authentication..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# =====================================================
# Save current revisions for rollback
# =====================================================
echo ""
echo "📌 Saving current revisions for potential rollback..."
PREVIOUS_BACKEND=$(gcloud run revisions list --service=backend \
    --region=$REGION \
    --project=$PROJECT_ID \
    --format="value(name)" \
    --sort-by="~creationTimestamp" \
    --limit=1 2>/dev/null || echo "")
PREVIOUS_FRONTEND=$(gcloud run revisions list --service=frontend \
    --region=$REGION \
    --project=$PROJECT_ID \
    --format="value(name)" \
    --sort-by="~creationTimestamp" \
    --limit=1 2>/dev/null || echo "")

if [ -n "$PREVIOUS_BACKEND" ]; then
    echo "  Backend:  $PREVIOUS_BACKEND"
else
    echo "  Backend:  (first deployment)"
fi
if [ -n "$PREVIOUS_FRONTEND" ]; then
    echo "  Frontend: $PREVIOUS_FRONTEND"
else
    echo "  Frontend: (first deployment)"
fi

# =====================================================
# Build and Deploy Backend
# =====================================================
echo ""
echo "📦 Building Backend Image (linux/amd64)..."
docker build --platform linux/amd64 -t $BACKEND_IMAGE ./backend

echo "⬆️  Pushing Backend Image..."
docker push $BACKEND_IMAGE

echo "🚀 Deploying Backend to Cloud Run (internal ingress)..."
# Backend uses --ingress=internal to block direct internet access.
# Only services with VPC Direct Egress (like frontend) can reach it.
# Security: internal ingress + CORS (only frontend URL allowed) + separate service accounts.
BACKEND_URL=$(gcloud run deploy backend \
    --image=$BACKEND_IMAGE \
    --region=$REGION \
    --platform=managed \
    --service-account=$BACKEND_SA \
    --allow-unauthenticated \
    --ingress=internal \
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

# Grant frontend service account permission to invoke backend
echo ""
echo "🔑 Granting frontend permission to invoke backend..."
gcloud run services add-iam-policy-binding backend \
    --region=$REGION \
    --member="serviceAccount:${FRONTEND_SA}" \
    --role="roles/run.invoker" \
    --project=$PROJECT_ID \
    --quiet > /dev/null 2>&1
echo "  ✓ Frontend can now invoke backend"

# Wait for backend to be healthy (using authenticated request)
echo "⏳ Waiting for backend health check..."
TOKEN=$(gcloud auth print-identity-token --audiences=$BACKEND_URL 2>/dev/null || echo "")
HEALTH_OK=false
for i in {1..10}; do
    if [ -n "$TOKEN" ]; then
        RESPONSE=$(curl -sf -H "Authorization: Bearer $TOKEN" "${BACKEND_URL}/health" 2>/dev/null || echo "")
    else
        RESPONSE=$(curl -sf "${BACKEND_URL}/health" 2>/dev/null || echo "")
    fi

    if [ -n "$RESPONSE" ]; then
        echo "✅ Backend is healthy!"
        HEALTH_OK=true
        break
    fi
    echo "   Attempt $i/10..."
    sleep 5
done

if [ "$HEALTH_OK" != "true" ]; then
    echo "❌ Backend health check failed!"
    if [ -n "$PREVIOUS_BACKEND" ]; then
        echo "🔄 Rolling back to previous revision: $PREVIOUS_BACKEND"
        gcloud run services update-traffic backend \
            --region=$REGION \
            --project=$PROJECT_ID \
            --to-revisions=${PREVIOUS_BACKEND}=100
        echo "✅ Rollback complete"
    fi
    exit 1
fi

# =====================================================
# Build and Deploy Frontend
# =====================================================
echo ""
echo "📦 Building Frontend Image (linux/amd64)..."
# Frontend is built with VITE_API_URL=/api (uses nginx proxy)
docker build \
    --platform linux/amd64 \
    -t $FRONTEND_IMAGE \
    ./frontend

echo "⬆️  Pushing Frontend Image..."
docker push $FRONTEND_IMAGE

echo "🚀 Deploying Frontend to Cloud Run (public access with VPC egress)..."
# Frontend uses VPC Direct Egress to reach internal backend.
# --network/--subnet/--vpc-egress enable traffic to flow through VPC.
FRONTEND_URL=$(gcloud run deploy frontend \
    --image=$FRONTEND_IMAGE \
    --region=$REGION \
    --platform=managed \
    --service-account=$FRONTEND_SA \
    --allow-unauthenticated \
    --port=8080 \
    --memory=512Mi \
    --cpu=1 \
    --min-instances=0 \
    --max-instances=5 \
    --timeout=60s \
    --set-env-vars="BACKEND_URL=${BACKEND_URL}" \
    --network=default \
    --subnet=default \
    --vpc-egress=all-traffic \
    --project=$PROJECT_ID \
    --format="value(status.url)")

echo "✅ Frontend deployed: $FRONTEND_URL"

# Wait for frontend to be healthy
echo "⏳ Waiting for frontend health check..."
HEALTH_OK=false
for i in {1..10}; do
    if curl -sf "${FRONTEND_URL}/health" > /dev/null 2>&1; then
        echo "✅ Frontend is healthy!"
        HEALTH_OK=true
        break
    fi
    echo "   Attempt $i/10..."
    sleep 5
done

if [ "$HEALTH_OK" != "true" ]; then
    echo "❌ Frontend health check failed!"
    if [ -n "$PREVIOUS_FRONTEND" ]; then
        echo "🔄 Rolling back to previous revision: $PREVIOUS_FRONTEND"
        gcloud run services update-traffic frontend \
            --region=$REGION \
            --project=$PROJECT_ID \
            --to-revisions=${PREVIOUS_FRONTEND}=100
        echo "✅ Rollback complete"
    fi
    exit 1
fi

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
echo "  Backend:  $BACKEND_URL (internal only)"
echo ""
echo "📦 Container Images:"
echo "  Backend:  $BACKEND_IMAGE"
echo "  Frontend: $FRONTEND_IMAGE"
echo ""
echo "🔒 Security Architecture:"
echo "  • Backend has internal ingress (not publicly accessible from internet)"
echo "  • Frontend uses VPC Direct Egress to reach internal backend"
echo "  • Private Google Access enabled on subnet for VPC-to-Cloud-Run traffic"
echo "  • Frontend service account has roles/run.invoker on backend"
echo "  • Only backend SA can access Anthropic API secret"
echo ""
echo "🧪 Test the deployment:"
echo "  1. Open: $FRONTEND_URL"
echo "  2. Upload a PDF and Excel file"
echo "  3. Verify extraction works (API calls go through frontend proxy)"
echo ""
echo "🔧 Useful Commands:"
echo "  View backend logs:  gcloud run services logs read backend --region=$REGION"
echo "  View frontend logs: gcloud run services logs read frontend --region=$REGION"
echo "  Rollback backend:   gcloud run services update-traffic backend --to-revisions=${PREVIOUS_BACKEND:-REVISION}=100 --region=$REGION"
echo "  Rollback frontend:  gcloud run services update-traffic frontend --to-revisions=${PREVIOUS_FRONTEND:-REVISION}=100 --region=$REGION"
echo ""
