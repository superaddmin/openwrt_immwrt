#!/usr/bin/env bash

set -euo pipefail

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    __build_ipk_sourced=0
else
    __build_ipk_sourced=1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
readonly SCRIPT_DIR
readonly REPO_ROOT

usage() {
    cat <<'EOF'
Usage: scripts/build-ipk.sh <device> [package-target ...]

Environment:
  WRT_IPK_TARGETS            Comma/newline/space separated package targets.
  WRT_IPK_ARTIFACT_PATTERNS  Optional comma/newline separated artifact glob patterns.

Examples:
  ./scripts/build-ipk.sh x64_immwrt luci-app-timecontrol
  WRT_IPK_TARGETS="feeds/custom_feed/lucky,package/luci-app-timecontrol" ./scripts/build-ipk.sh x64_immwrt
EOF
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "$value"
}

split_to_lines() {
    local raw="${1:-}"
    if [[ -z "$raw" ]]; then
        return 0
    fi

    printf '%s\n' "$raw" | tr ',;	 ' '\n\n\n\n'
}

normalize_package_target() {
    local target
    target=$(trim "$1")

    if [[ -z "$target" ]]; then
        echo "Package target cannot be empty" >&2
        return 1
    fi

    case "$target" in
        package/*)
            printf '%s\n' "$target"
            ;;
        feeds/*)
            printf 'package/%s\n' "$target"
            ;;
        *)
            printf 'package/%s\n' "$target"
            ;;
    esac
}

artifact_matches_pattern() {
    local relative_path="$1"
    local pattern="$2"
    local basename_path

    basename_path=$(basename "$relative_path")

    if [[ "$relative_path" == $pattern ]]; then
        return 0
    fi

    if [[ "$basename_path" == $pattern ]]; then
        return 0
    fi

    return 1
}

collect_targets() {
    local -n output_ref=$1
    shift || true
    local item
    local normalized

    output_ref=()

    for item in "$@"; do
        item=$(trim "$item")
        [[ -z "$item" ]] && continue
        normalized=$(normalize_package_target "$item")
        output_ref+=("$normalized")
    done

    while IFS= read -r item; do
        item=$(trim "$item")
        [[ -z "$item" ]] && continue
        normalized=$(normalize_package_target "$item")
        output_ref+=("$normalized")
    done < <(split_to_lines "${WRT_IPK_TARGETS:-}")

    if [[ ${#output_ref[@]} -eq 0 ]]; then
        echo "At least one package target is required." >&2
        usage >&2
        return 1
    fi
}

collect_patterns() {
    local -n output_ref=$1
    local item

    output_ref=()

    while IFS= read -r item; do
        item=$(trim "$item")
        [[ -z "$item" ]] && continue
        output_ref+=("$item")
    done < <(split_to_lines "${WRT_IPK_ARTIFACT_PATTERNS:-}")
}

ensure_action_build_ready() {
    local device="$1"

    echo "Preparing action_build for $device via debug build..."
    bash "$REPO_ROOT/build.sh" "$device" debug
}

list_ipk_files() {
    local build_dir="$1"

    find "$build_dir/bin" -type f -name '*.ipk' | sort
}

compile_targets() {
    local build_dir="$1"
    shift
    local target

    pushd "$build_dir" >/dev/null

    for target in "$@"; do
        echo "Cleaning previous outputs for $target"
        make "$target/clean"
        echo "Downloading sources for $target"
        make "$target/download" -j"$(($(nproc) * 2))"
        echo "Compiling $target"
        make "$target/compile" -j"$(($(nproc) + 1))" || make "$target/compile" -j1 V=s
    done

    popd >/dev/null
}

copy_matching_ipks() {
    local build_dir="$1"
    local artifact_dir="$2"
    local stamp_file="$3"
    shift 3
    local patterns=("$@")
    local all_after=()
    local path
    local rel_path
    local matched=0

    mapfile -t all_after < <(list_ipk_files "$build_dir")

    for path in "${all_after[@]}"; do
        rel_path="${path#"$build_dir/bin/"}"

        if [[ ! "$path" -nt "$stamp_file" ]]; then
            continue
        fi

        if [[ ${#patterns[@]} -gt 0 ]]; then
            local pattern_matched=0
            local pattern
            for pattern in "${patterns[@]}"; do
                if artifact_matches_pattern "$rel_path" "$pattern"; then
                    pattern_matched=1
                    break
                fi
            done
            [[ $pattern_matched -eq 1 ]] || continue
        fi

        cp -f "$path" "$artifact_dir/"
        matched=1
    done

    if [[ $matched -ne 1 ]]; then
        echo "No .ipk artifacts matched the current build output." >&2
        return 1
    fi
}

write_metadata_files() {
    local artifact_dir="$1"
    local device="$2"
    shift 2
    local targets=("$@")
    local source_lock="$REPO_ROOT/action_build/.source-lock"
    local artifact

    printf '%s\n' "${targets[@]}" >"$artifact_dir/package-targets.txt"

    if [[ -n "${WRT_IPK_ARTIFACT_PATTERNS:-}" ]]; then
        split_to_lines "$WRT_IPK_ARTIFACT_PATTERNS" | sed '/^[[:space:]]*$/d' >"$artifact_dir/artifact-patterns.txt"
    fi

    if [[ -f "$source_lock" ]]; then
        cp -f "$source_lock" "$artifact_dir/source-lock.txt"
    fi

    pushd "$artifact_dir" >/dev/null
    : > sha256sums.txt
    for artifact in *.ipk; do
        [[ -f "$artifact" ]] || continue
        sha256sum "$artifact" >> sha256sums.txt
    done
    popd >/dev/null

    echo "$device" >"$artifact_dir/device.txt"
}

main() {
    local device="${1:-}"
    local build_dir="$REPO_ROOT/action_build"
    local artifact_root="$REPO_ROOT/ipk_artifacts"
    local artifact_dir
    local stamp_file
    local targets=()
    local patterns=()

    if [[ -z "$device" ]]; then
        usage >&2
        exit 1
    fi

    shift || true

    collect_targets targets "$@"
    collect_patterns patterns

    ensure_action_build_ready "$device"

    if [[ ! -d "$build_dir" ]]; then
        echo "Build directory not found: $build_dir" >&2
        exit 1
    fi

    artifact_dir="$artifact_root/$device"
    rm -rf "$artifact_dir"
    mkdir -p "$artifact_dir"

    stamp_file=$(mktemp)
    trap 'rm -f "$stamp_file"' RETURN

    compile_targets "$build_dir" "${targets[@]}"
    copy_matching_ipks "$build_dir" "$artifact_dir" "$stamp_file" "${patterns[@]}"
    write_metadata_files "$artifact_dir" "$device" "${targets[@]}"

    echo "Collected IPK artifacts:"
    find "$artifact_dir" -maxdepth 1 -type f | sort
}

if [[ $__build_ipk_sourced -eq 0 ]]; then
    main "$@"
fi
