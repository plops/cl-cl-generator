#!/bin/bash
if [ -f ../../../../../../dotemacs/.emacs ]; then
  cp ../../../../../../dotemacs/.emacs .
elif [ -f /home/kiel/stage/dotemacs/.emacs ]; then
  cp /home/kiel/stage/dotemacs/.emacs .
fi

./build.sh
docker build -t my-ai-env:latest .
rm -f .emacs
