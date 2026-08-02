#!/bin/bash
# Deploy quizQuestionEditor LWC to a target Salesforce org.
# Usage: ./deploy.sh [org-alias]
# Example: ./deploy.sh pharma-prod

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ORG="${1:-}"

if ! command -v sf &> /dev/null; then
    echo "Error: Salesforce CLI (sf) is not installed."
    exit 1
fi

if [ -z "$TARGET_ORG" ]; then
    echo "Usage: ./deploy.sh <org-alias>"
    echo ""
    echo "Available orgs:"
    sf org list
    exit 1
fi

echo "Deploying quizQuestionEditor to: $TARGET_ORG"
sf project deploy start \
    --source-dir "$SCRIPT_DIR/lwc/quizQuestionEditor" \
    -o "$TARGET_ORG" \
    --wait 10

echo "Done. Add the component to your Learning Material record page in App Builder."
