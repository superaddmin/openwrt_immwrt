#!/usr/bin/env bash

source_repo_root() {
    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    cd "$script_dir/.." && pwd
}

read_ini_value() {
    local ini_file="$1"
    local key="$2"

    awk -F"=" -v key="$key" '
        $1 == key {
            value = $0
            sub("^[^=]*=", "", value)
            print value
            exit
        }
    ' "$ini_file"
}

resolve_device_source() {
    local device="$1"
    local repo_root="${2:-$(source_repo_root)}"
    local ini_file="$repo_root/wrt_core/compilecfg/$device.ini"
    local build_dir

    if [[ -z "$device" ]]; then
        echo "Device is required" >&2
        return 1
    fi

    if [[ ! -f "$ini_file" ]]; then
        echo "INI file not found: $ini_file" >&2
        return 1
    fi

    build_dir=$(read_ini_value "$ini_file" "BUILD_DIR")
    if [[ -z "$build_dir" ]]; then
        echo "BUILD_DIR is not configured in $ini_file" >&2
        return 1
    fi

    printf '%s\n' "sources/$build_dir"
}

source_commit() {
    local repo_root="$1"
    local source_path="$2"

    git -C "$repo_root/$source_path" rev-parse HEAD
}

source_remote_url() {
    local repo_root="$1"
    local source_path="$2"
    local source_url

    source_url=$(git -C "$repo_root" config --file .gitmodules --get "submodule.$source_path.url" || true)
    if [[ -n "$source_url" ]]; then
        printf '%s\n' "$source_url"
        return 0
    fi

    git -C "$repo_root/$source_path" config --get remote.origin.url
}

write_source_lock() {
    local repo_root="$1"
    local device="$2"
    local source_path="$3"
    local output_file="$4"
    local source_url
    local commit
    local branch

    source_url=$(source_remote_url "$repo_root" "$source_path")
    commit=$(source_commit "$repo_root" "$source_path")
    branch=$(git -C "$repo_root" config --file .gitmodules --get "submodule.$source_path.branch" || true)

    mkdir -p "$(dirname "$output_file")"
    {
        printf 'device=%s\n' "$device"
        printf 'source_path=%s\n' "$source_path"
        printf 'source_url=%s\n' "$source_url"
        printf 'source_branch=%s\n' "${branch:-unknown}"
        printf 'source_commit=%s\n' "$commit"
        printf 'locked_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$output_file"
}
