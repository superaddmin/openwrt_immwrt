#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/source-common.sh"

main() {
    local source_id="${1:-}"
    local repo_root
    local source_path
    local patch_dir
    local patch_file

    if [[ -z "$source_id" ]]; then
        echo "Usage: $0 <source-id>" >&2
        exit 1
    fi

    repo_root=$(source_repo_root)
    source_path="$repo_root/sources/$source_id"
    patch_dir="$repo_root/patches/local/$source_id"

    if [[ ! -e "$source_path/.git" ]]; then
        echo "Source submodule is not initialized: sources/$source_id" >&2
        exit 1
    fi

    mkdir -p "$patch_dir"
    patch_file="$patch_dir/$(date -u +%Y%m%d%H%M%S)-working-tree.patch"

    git -C "$source_path" diff --binary >"$patch_file"

    if [[ ! -s "$patch_file" ]]; then
        rm -f "$patch_file"
        echo "No working tree changes in $source_id"
        exit 0
    fi

    echo "Exported patch: $patch_file"
}

main "$@"
