#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

PULL_FLAG=""

# Parse arguments
for arg in "$@"; do
  case $arg in
    --pull)
      PULL_FLAG="--pull always"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--pull]"
      echo "  --pull    Force update the base OpenClaw Docker image before building."
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: $0 [--pull]"
      exit 1
      ;;
  esac
done

echo "🚀 Starting OpenClaw Service..."

if [ -n "$PULL_FLAG" ]; then
  echo "⬇️  Flag '--pull' detected: Forcing download of the latest base image..."
fi

# 啟動並編譯，若有 $PULL_FLAG 則會帶上 --pull always
docker compose up -d --build $PULL_FLAG

echo "✅ OpenClaw Service is up and running!"
