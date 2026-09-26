#!/bin/zsh
# Wraps page.html (the page body, also used as the artifact preview) into a standalone index.html
# and refreshes the download zip from ../build/mAhgic.app.
set -euo pipefail
cd "$(dirname "$0")"
{
  print -r -- '<!doctype html>'
  print -r -- '<html lang="en">'
  print -r -- '<head>'
  print -r -- '<meta charset="utf-8">'
  print -r -- '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">'
  cat page.html
  print -r -- '</html>'
} > index.html
if [[ -d ../build/mAhgic.app ]]; then
  mkdir -p downloads
  rm -f downloads/mAhgic-1.0.zip
  ditto -c -k --keepParent ../build/mAhgic.app downloads/mAhgic-1.0.zip
fi
echo "Built website/index.html"
