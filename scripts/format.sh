#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

exec swift run -c release --package-path "$repo_root/BuildTools" swiftformat "$repo_root" --config "$repo_root/.swiftformat" "$@"
