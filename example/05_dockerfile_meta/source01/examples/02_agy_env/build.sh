#!/bin/bash
set -e
# Navigate to the script's directory
cd "$(dirname "$0")"

echo "Generating Agy Env Dockerfile via SBCL..."
sbcl --load gen_agy_env.lisp --eval "(quit)"
echo "Dockerfile generated successfully."
