#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=source-common.sh
source "$SCRIPT_DIR/source-common.sh"

TEST_TMP_DIR=""

assert_line_present() {
    local expected="$1"
    local content="$2"
    local message="$3"

    if ! grep -Fxq "$expected" <<<"$content"; then
        echo "ASSERT_LINE_PRESENT failed: $message" >&2
        echo "  missing line: $expected" >&2
        exit 1
    fi
}

assert_line_absent() {
    local unexpected="$1"
    local content="$2"
    local message="$3"

    if grep -Fxq "$unexpected" <<<"$content"; then
        echo "ASSERT_LINE_ABSENT failed: $message" >&2
        echo "  unexpected line: $unexpected" >&2
        exit 1
    fi
}

assert_file_contains() {
    local file="$1"
    local expected="$2"
    local message="$3"

    if ! grep -Fxq "$expected" "$file"; then
        echo "ASSERT_FILE_CONTAINS failed: $message" >&2
        echo "  missing line: $expected" >&2
        exit 1
    fi
}

assert_file_not_contains() {
    local file="$1"
    local unexpected="$2"
    local message="$3"

    if grep -Fxq "$unexpected" "$file"; then
        echo "ASSERT_FILE_NOT_CONTAINS failed: $message" >&2
        echo "  unexpected line: $unexpected" >&2
        exit 1
    fi
}

main() {
    local rsync_excludes
    rsync_excludes=$(source_sync_rsync_excludes)

    assert_line_present "/feeds" "$rsync_excludes" \
        "rsync excludes should anchor root feeds cache"
    assert_line_present "/package/feeds" "$rsync_excludes" \
        "rsync excludes should anchor root package/feeds cache"
    assert_line_absent "feeds" "$rsync_excludes" \
        "rsync excludes must not use unanchored feeds pattern"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    TEST_TMP_DIR="$tmp_dir"
    trap 'if [[ -n "${TEST_TMP_DIR:-}" ]]; then rm -rf "$TEST_TMP_DIR"; fi' EXIT

    mkdir -p "$tmp_dir/src/scripts" "$tmp_dir/src/feeds" "$tmp_dir/src/bin"
    touch "$tmp_dir/src/scripts/feeds"
    touch "$tmp_dir/src/feeds/cache"
    touch "$tmp_dir/src/bin/output"

    local tar_args=()
    local item
    while IFS= read -r item; do
        [[ -n "$item" ]] || continue
        tar_args+=(--exclude="$item")
    done < <(source_sync_tar_excludes)

    tar "${tar_args[@]}" -C "$tmp_dir/src" -cf "$tmp_dir/source.tar" .
    tar -tf "$tmp_dir/source.tar" | sort >"$tmp_dir/list.txt"

    assert_file_contains "$tmp_dir/list.txt" "./scripts/feeds" \
        "tar excludes should preserve OpenWrt scripts/feeds helper"
    assert_file_not_contains "$tmp_dir/list.txt" "./feeds/" \
        "tar excludes should remove root feeds cache"
    assert_file_not_contains "$tmp_dir/list.txt" "./bin/" \
        "tar excludes should remove root bin cache"

    echo "source-common tests passed"
}

main "$@"
