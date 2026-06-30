#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/source-common.sh"

contains_source() {
    local wanted="$1"
    shift
    local existing

    for existing in "$@"; do
        if [[ "$existing" == "$wanted" ]]; then
            return 0
        fi
    done

    return 1
}

main() {
    local repo_root
    local devices=()
    local seen_sources=()
    local device
    local source_path
    local source_id

    repo_root=$(source_repo_root)

    if [[ $# -eq 0 ]]; then
        while IFS= read -r device; do
            devices+=("$device")
        done < <(find "$repo_root/wrt_core/compilecfg" -name '*.ini' -exec basename {} .ini \; | sort)
    else
        devices=("$@")
    fi

    for device in "${devices[@]}"; do
        source_path=$(resolve_device_source "$device" "$repo_root")
        source_id=${source_path#sources/}

        if contains_source "$source_id" "${seen_sources[@]}"; then
            continue
        fi
        seen_sources+=("$source_id")

        if [[ ! -e "$repo_root/$source_path/.git" ]]; then
            echo "Skipping uninitialized source: $source_path" >&2
            continue
        fi

        write_source_lock "$repo_root" "$device" "$source_path" "$repo_root/metadata/sources/$source_id.lock"
        echo "Updated metadata/sources/$source_id.lock"
    done
}

main "$@"
