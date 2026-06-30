#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/source-common.sh"

usage() {
    echo "Usage: $0 <device> [--dry-run]"
}

assert_build_copy_path() {
    local repo_root="$1"
    local build_copy_path="$2"
    local expected_path="$repo_root/action_build"

    if [[ "$build_copy_path" != "$expected_path" ]]; then
        echo "Refusing to prepare unexpected build path: $build_copy_path" >&2
        exit 1
    fi
}

sync_with_tar() {
    local source_abs="$1"
    local build_copy_path="$2"
    local tar_args=()
    local item

    while IFS= read -r item; do
        [[ -n "$item" ]] || continue
        tar_args+=(--exclude="$item")
    done < <(source_sync_tar_excludes)

    tar "${tar_args[@]}" -C "$source_abs" -cf - . | tar -C "$build_copy_path" -xf -
}

sync_with_tar_preserving_cache() {
    local source_abs="$1"
    local build_copy_path="$2"
    local cache_tmp
    local item

    cache_tmp=$(mktemp -d)

    for item in .ccache staging_dir; do
        if [[ -d "$build_copy_path/$item" ]]; then
            mv "$build_copy_path/$item" "$cache_tmp/$item"
        fi
    done

    rm -rf "$build_copy_path"
    mkdir -p "$build_copy_path"
    sync_with_tar "$source_abs" "$build_copy_path"

    for item in .ccache staging_dir; do
        if [[ -d "$cache_tmp/$item" ]]; then
            mv "$cache_tmp/$item" "$build_copy_path/$item"
        fi
    done

    rm -rf "$cache_tmp"
}

sync_with_rsync() {
    local source_abs="$1"
    local build_copy_path="$2"
    local rsync_args=(-a --delete)
    local item

    while IFS= read -r item; do
        [[ -n "$item" ]] || continue
        rsync_args+=(--exclude "$item")
    done < <(source_sync_rsync_excludes)

    rsync "${rsync_args[@]}" "$source_abs/" "$build_copy_path/"
}

main() {
    local device="${1:-}"
    local dry_run=0
    local repo_root
    local source_path
    local source_abs
    local build_copy_path

    if [[ -z "$device" ]]; then
        usage >&2
        exit 1
    fi

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown argument: $1" >&2
                usage >&2
                exit 1
                ;;
        esac
        shift
    done

    repo_root=$(source_repo_root)
    source_path=$(resolve_device_source "$device" "$repo_root")
    source_abs="$repo_root/$source_path"
    build_copy_path="$repo_root/action_build"

    if [[ ! -e "$source_abs/.git" ]]; then
        echo "Source submodule is not initialized: $source_path" >&2
        echo "Run: git submodule update --init --depth 1 -- $source_path" >&2
        exit 1
    fi

    assert_build_copy_path "$repo_root" "$build_copy_path"

    if [[ "$dry_run" -eq 1 ]]; then
        echo "Would prepare $build_copy_path from $source_abs"
        source_sync_excludes | sed 's/^/exclude: /'
        exit 0
    fi

    if command -v rsync >/dev/null 2>&1; then
        mkdir -p "$build_copy_path"
        sync_with_rsync "$source_abs" "$build_copy_path"
    else
        sync_with_tar_preserving_cache "$source_abs" "$build_copy_path"
    fi

    write_source_lock "$repo_root" "$device" "$source_path" "$build_copy_path/.source-lock"
    echo "Prepared $build_copy_path from $source_abs"
    cat "$build_copy_path/.source-lock"
}

main "$@"
