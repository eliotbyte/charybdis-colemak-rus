#!/usr/bin/env bash
sed -i 's/\r$//' "$0" /work/scripts/docker-build.sh 2>/dev/null || true
exec bash /work/scripts/docker-build.sh "${1:-firmware}"
