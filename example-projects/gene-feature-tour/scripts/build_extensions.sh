#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

cd "$repo_root"
echo "Running from $repo_root: nimble buildext"
exec nimble buildext
