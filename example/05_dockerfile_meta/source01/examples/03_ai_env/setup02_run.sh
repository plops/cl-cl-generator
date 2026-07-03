#!/bin/bash
# Create the folder on your host first so Docker doesn't generate it as 'root'
mkdir -p "$HOME/.gemini"

docker run -it \
  -e ANTIGRAVITY_PLAINTEXT_AUTH=1 \
  -v "$HOME/.gemini:/root/.gemini" \
  -v "/home/kiel/stage:/workspace/src" \
  -v my-ai-env-cargo-cache:/root/.cargo \
  my-ai-env:latest
