#!/bin/bash
set -e

TEMPLATE_FILE="zeabur-template-openclaw-devbox.yaml"
PROJECT_NAME="${1:-openclaw-devbox-$(date +%Y%m%d%H%M%S)}"
REGION="${2:-hkg1}"

echo "Creating project: $PROJECT_NAME in region: $REGION"
npx zeabur@latest project create -n "$PROJECT_NAME" -r "$REGION"

PROJECT_ID=$(npx zeabur@latest project list | grep "$PROJECT_NAME" | awk '{print $1}')
echo "Project ID: $PROJECT_ID"

echo "Deploying template..."
npx zeabur@latest template deploy -f "$TEMPLATE_FILE" --project-id "$PROJECT_ID"

echo "Done! Project: $PROJECT_NAME deployed."
