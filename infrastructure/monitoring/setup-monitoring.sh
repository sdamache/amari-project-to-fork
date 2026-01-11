#!/bin/bash

# Setup Monitoring and Alerting for Logistics Data Extractor
# Creates uptime checks, alert policies, and a monitoring dashboard

set -e

# Load environment variables
if [ -f .env ]; then
    source .env
fi

# Configuration
PROJECT_ID=${GCP_PROJECT_ID:-"unique-hash-367919"}
REGION=${GCP_REGION:-"us-central1"}
NOTIFICATION_EMAIL=${NOTIFICATION_EMAIL:-""}

echo "📊 Setting up Monitoring and Alerting"
echo "======================================"
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo ""

# Enable required APIs
echo "📡 Enabling monitoring APIs..."
gcloud services enable \
    monitoring.googleapis.com \
    logging.googleapis.com \
    clouderrorreporting.googleapis.com \
    cloudtrace.googleapis.com \
    --project=$PROJECT_ID

# Get service URLs
echo "🔍 Getting service URLs..."
BACKEND_URL=$(gcloud run services describe backend --region=${REGION} --project=${PROJECT_ID} --format="value(status.url)" 2>/dev/null || echo "")
FRONTEND_URL=$(gcloud run services describe frontend --region=${REGION} --project=${PROJECT_ID} --format="value(status.url)" 2>/dev/null || echo "")

if [ -z "$BACKEND_URL" ]; then
    echo "⚠️  Backend service not found. Deploy services first."
    echo "   Run: ./infrastructure/deploy-to-cloud-run.sh"
    exit 1
fi

echo "  Backend: $BACKEND_URL"
echo "  Frontend: $FRONTEND_URL"
echo ""

# Create notification channel if email is provided
if [ -n "$NOTIFICATION_EMAIL" ]; then
    echo "📧 Creating notification channel..."

    NOTIFICATION_CHANNEL_CONFIG=$(cat << EOF
{
  "type": "email",
  "displayName": "Logistics Extractor Alerts",
  "description": "Email notifications for Logistics Data Extractor",
  "labels": {
    "email_address": "$NOTIFICATION_EMAIL"
  }
}
EOF
)

    echo "$NOTIFICATION_CHANNEL_CONFIG" > /tmp/notification-channel.json

    NOTIFICATION_CHANNEL_ID=$(gcloud alpha monitoring channels create \
        --channel-content-from-file=/tmp/notification-channel.json \
        --project=$PROJECT_ID \
        --format="value(name)" 2>/dev/null | tail -1 || echo "")

    rm -f /tmp/notification-channel.json

    if [ -n "$NOTIFICATION_CHANNEL_ID" ]; then
        echo "  Created: $NOTIFICATION_CHANNEL_ID"
    fi
fi

# Create uptime checks
echo "🏥 Creating uptime checks..."

# Backend health check
BACKEND_HOST=$(echo $BACKEND_URL | sed 's|https://||' | sed 's|/.*||')
gcloud monitoring uptime-checks create http backend-health-check \
    --display-name="Backend Health Check" \
    --uri="https://${BACKEND_HOST}/health" \
    --check-interval=60 \
    --timeout=10 \
    --project=$PROJECT_ID 2>/dev/null || echo "  Backend uptime check may already exist"

# Frontend health check
if [ -n "$FRONTEND_URL" ]; then
    FRONTEND_HOST=$(echo $FRONTEND_URL | sed 's|https://||' | sed 's|/.*||')
    gcloud monitoring uptime-checks create http frontend-health-check \
        --display-name="Frontend Health Check" \
        --uri="https://${FRONTEND_HOST}/health" \
        --check-interval=60 \
        --timeout=10 \
        --project=$PROJECT_ID 2>/dev/null || echo "  Frontend uptime check may already exist"
fi

echo "✅ Uptime checks created"

# Create alert policies
echo "🚨 Creating alert policies..."

# High error rate alert policy
cat > /tmp/error-rate-policy.json << 'EOF'
{
  "displayName": "High Error Rate - Logistics Extractor",
  "documentation": {
    "content": "Alert when error rate exceeds 5% over 5 minutes. Check Cloud Run logs for details.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Error rate > 5%",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=monitoring.regex.full_match(\"backend|frontend\") AND metric.type=\"run.googleapis.com/request_count\" AND metric.labels.response_code_class=\"5xx\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0.05,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_RATE",
            "crossSeriesReducer": "REDUCE_SUM",
            "groupByFields": ["resource.labels.service_name"]
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true
}
EOF

gcloud alpha monitoring policies create \
    --policy-from-file=/tmp/error-rate-policy.json \
    --project=$PROJECT_ID 2>/dev/null || echo "  Error rate policy may already exist"

# High latency alert policy
cat > /tmp/latency-policy.json << 'EOF'
{
  "displayName": "High Latency - Logistics Extractor",
  "documentation": {
    "content": "Alert when P95 latency exceeds 10 seconds. LLM extraction is expected to be slow.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Latency P95 > 10s",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"backend\" AND metric.type=\"run.googleapis.com/request_latencies\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 10000,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_PERCENTILE_95"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true
}
EOF

gcloud alpha monitoring policies create \
    --policy-from-file=/tmp/latency-policy.json \
    --project=$PROJECT_ID 2>/dev/null || echo "  Latency policy may already exist"

# Service unavailable alert policy (CRITICAL)
# Triggers when uptime check fails for 2+ consecutive checks (2 minutes)
cat > /tmp/availability-policy.json << EOF
{
  "displayName": "Service Unavailable - Logistics Extractor",
  "documentation": {
    "content": "CRITICAL: Service is down. Check Cloud Run status immediately.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Uptime check failed for 2+ minutes",
      "conditionThreshold": {
        "filter": "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\"",
        "comparison": "COMPARISON_LT",
        "thresholdValue": 1,
        "duration": "120s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_NEXT_OLDER",
            "crossSeriesReducer": "REDUCE_COUNT_FALSE"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true
}
EOF

gcloud alpha monitoring policies create \
    --policy-from-file=/tmp/availability-policy.json \
    --project=$PROJECT_ID 2>/dev/null || echo "  Availability policy may already exist"

rm -f /tmp/error-rate-policy.json /tmp/latency-policy.json /tmp/availability-policy.json

echo "✅ Alert policies created"

# Create monitoring script for local use
cat > /tmp/monitor-services.sh << 'SCRIPT'
#!/bin/bash
# Quick monitoring script for Logistics Data Extractor

PROJECT_ID=${GCP_PROJECT_ID:-"unique-hash-367919"}
REGION=${GCP_REGION:-"us-central1"}

case "${1:-status}" in
    "status")
        echo "🏥 Service Health Status"
        echo "========================"
        for service in backend frontend; do
            URL=$(gcloud run services describe $service --region=$REGION --project=$PROJECT_ID --format="value(status.url)" 2>/dev/null)
            if [ -n "$URL" ]; then
                STATUS=$(curl -sf "${URL}/health" && echo "✅ Healthy" || echo "❌ Unhealthy")
                echo "$service: $STATUS ($URL)"
            else
                echo "$service: ⚠️ Not deployed"
            fi
        done
        ;;
    "logs")
        SERVICE=${2:-backend}
        echo "📋 Recent logs for $SERVICE"
        gcloud run services logs read $SERVICE --region=$REGION --project=$PROJECT_ID --limit=50
        ;;
    "errors")
        echo "❌ Recent errors"
        gcloud logging read "resource.type=cloud_run_revision AND severity>=ERROR" \
            --limit=20 --project=$PROJECT_ID \
            --format="table(timestamp,resource.labels.service_name,textPayload)"
        ;;
    *)
        echo "Usage: $0 [status|logs|errors]"
        echo "  status - Check health of all services"
        echo "  logs [service] - View recent logs (default: backend)"
        echo "  errors - View recent errors across all services"
        ;;
esac
SCRIPT

cp /tmp/monitor-services.sh ./infrastructure/monitoring/monitor-services.sh
chmod +x ./infrastructure/monitoring/monitor-services.sh
rm -f /tmp/monitor-services.sh

echo ""
echo "✅ Monitoring Setup Complete!"
echo "======================================"
echo ""
echo "📋 What was created:"
echo "  • Uptime checks for backend and frontend"
echo "  • Alert policy: High Error Rate (>5%)"
echo "  • Alert policy: High Latency (P95 > 10s)"
echo "  • Alert policy: Service Unavailable (CRITICAL - 2+ minute downtime)"
echo "  • Local monitoring script: ./infrastructure/monitoring/monitor-services.sh"
echo ""
echo "🔧 Quick commands:"
echo "  ./infrastructure/monitoring/monitor-services.sh status  # Check service health"
echo "  ./infrastructure/monitoring/monitor-services.sh logs    # View backend logs"
echo "  ./infrastructure/monitoring/monitor-services.sh errors  # View errors"
echo ""
echo "📊 View in Console:"
echo "  https://console.cloud.google.com/monitoring?project=$PROJECT_ID"
echo "  https://console.cloud.google.com/run?project=$PROJECT_ID"
