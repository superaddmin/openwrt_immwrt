#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/source-common.sh"

usage() {
    echo "Usage: $0 <device> [--skip-submodule-exists]"
}

normalize_url() {
    local url="$1"
    url="${url%%|*}"
    url="${url%%;*}"
    url="${url%;}"
    url="${url%\\}"
    url="${url%),}"
    url="${url%)}"
    url="${url%,}"
    printf '%s\n' "$url"
}

is_registered_dependency() {
    local url="$1"
    local metadata_file="$2"

    if awk -F'\t' -v url="$url" 'NR > 1 && $3 == url { found = 1 } END { exit found ? 0 : 1 }' "$metadata_file"; then
        return 0
    fi

    case "$url" in
        https://\$*)
            awk -F'\t' '$2 == "package-source-url" { found = 1 } END { exit found ? 0 : 1 }' "$metadata_file"
            ;;
        https://github.com/v2fly/geoip/releases/download/*)
            awk -F'\t' '$2 == "v2fly-geoip" { found = 1 } END { exit found ? 0 : 1 }' "$metadata_file"
            ;;
        https://api.github.com/repos/*)
            awk -F'\t' '$2 == "github-releases" { found = 1 } END { exit found ? 0 : 1 }' "$metadata_file"
            ;;
        *)
            return 1
            ;;
    esac
}

main() {
    local device="${1:-}"
    local skip_submodule_exists=0
    local repo_root
    local source_path
    local metadata_file
    local lock_file
    local submodule_path
    local url
    local missing_urls=()

    if [[ -z "$device" ]]; then
        usage >&2
        exit 1
    fi

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-submodule-exists)
                skip_submodule_exists=1
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
    metadata_file="$repo_root/metadata/external-dependencies.tsv"
    lock_file="$repo_root/action_build/.source-lock"

    submodule_path=$(git -C "$repo_root" config --file .gitmodules --get "submodule.$source_path.path" || true)
    if [[ "$submodule_path" != "$source_path" ]]; then
        echo "Source path $source_path is not registered in .gitmodules" >&2
        exit 1
    fi

    if [[ "$skip_submodule_exists" -ne 1 && ! -e "$repo_root/$source_path/.git" ]]; then
        echo "Submodule worktree is not initialized: $source_path" >&2
        echo "Run: git submodule update --init --depth 1 -- $source_path" >&2
        exit 1
    fi

    if [[ ! -f "$metadata_file" ]]; then
        echo "External dependency metadata is missing: $metadata_file" >&2
        exit 1
    fi

    while IFS= read -r raw_url; do
        url=$(normalize_url "$raw_url")
        [[ -n "$url" ]] || continue
        if ! is_registered_dependency "$url" "$metadata_file"; then
            missing_urls+=("$url")
        fi
    done < <(
        {
            grep -RhoE 'https://[^"'\''[:space:]<>]+' "$repo_root/wrt_core"/*.sh "$repo_root/wrt_core/modules"/*.sh "$repo_root/wrt_core/compilecfg"/*.ini
        } | sort -u
    )

    if [[ ${#missing_urls[@]} -ne 0 ]]; then
        echo "Unregistered external dependencies:" >&2
        printf '  %s\n' "${missing_urls[@]}" >&2
        exit 1
    fi

    if [[ "$skip_submodule_exists" -ne 1 ]]; then
        write_source_lock "$repo_root" "$device" "$source_path" "$lock_file"
    fi

    echo "Source validation passed for $device -> $source_path"
}

main "$@"
