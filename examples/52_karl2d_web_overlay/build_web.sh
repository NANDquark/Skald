#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

odin run karl2d/build_web -- examples/52_karl2d_web_overlay "$@"
