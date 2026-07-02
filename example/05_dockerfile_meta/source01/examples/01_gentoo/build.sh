#!/bin/bash
set -e
# Navigate to the script's directory
cd "$(dirname "$0")"

echo "Generating Gentoo Dockerfile via SBCL..."
sbcl --load gen_gentoo.lisp --eval "(quit)"
echo "Dockerfile generated successfully."
