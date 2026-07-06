#!/bin/bash
set -e

# Navigate to the script's directory
cd "$(dirname "$0")"

echo "Building temporary dev target 'base' stage..."
export DOCKER_BUILDKIT=1
docker build --target base -t gentoo-z6-min-openrc-dev .

echo "Entering interactive bash shell in container..."
docker run --rm -it \
  -v "$(pwd)/distfiles:/var/cache/distfiles" \
  -v "$(pwd)/binpkgs:/var/cache/binpkgs" \
  gentoo-z6-min-openrc-dev /bin/bash
