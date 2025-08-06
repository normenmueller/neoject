#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bats "$DIR/spec/offline.bats"
bats "$DIR/spec/online.bats"

