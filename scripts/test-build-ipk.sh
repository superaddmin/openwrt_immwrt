#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=build-ipk.sh
source "$SCRIPT_DIR/build-ipk.sh"

TEST_TMP_DIR=""

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "$expected" != "$actual" ]]; then
        echo "ASSERT_EQ failed: $message" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        exit 1
    fi
}

assert_true() {
    local message="$1"
    shift

    if ! "$@"; then
        echo "ASSERT_TRUE failed: $message" >&2
        exit 1
    fi
}

main() {
    local targets=()

    assert_eq "package/luci-app-timecontrol" \
        "$(normalize_package_target "luci-app-timecontrol")" \
        "plain package names should normalize to package/<name>"

    assert_eq "package/luci-app-timecontrol" \
        "$(normalize_package_target "package/luci-app-timecontrol")" \
        "package/ targets should stay unchanged"

    assert_eq "package/feeds/custom_feed/lucky" \
        "$(normalize_package_target "feeds/custom_feed/lucky")" \
        "feeds/ targets should normalize into package/feeds/"

    assert_eq "package/feeds/custom_feed/lucky" \
        "$(normalize_package_target "package/feeds/custom_feed/lucky")" \
        "package/feeds targets should stay unchanged"

    WRT_IPK_TARGETS=""
    collect_targets targets "luci-app-timecontrol"
    assert_eq "1" "${#targets[@]}" \
        "CLI package targets should be collected"
    assert_eq "package/luci-app-timecontrol" "${targets[0]}" \
        "CLI package targets should be normalized"

    WRT_IPK_TARGETS="luci-app-timecontrol,feeds/custom_feed/lucky"
    collect_targets targets
    assert_eq "2" "${#targets[@]}" \
        "environment package targets should be collected"
    assert_eq "package/luci-app-timecontrol" "${targets[0]}" \
        "first environment package target should be normalized"
    assert_eq "package/feeds/custom_feed/lucky" "${targets[1]}" \
        "second environment package target should be normalized"

    local patterns=()
    WRT_IPK_ARTIFACT_PATTERNS="*/luci-app-timecontrol_*.ipk"
    collect_patterns patterns
    assert_eq "1" "${#patterns[@]}" \
        "single environment artifact pattern should be collected"
    assert_eq "*/luci-app-timecontrol_*.ipk" "${patterns[0]}" \
        "environment artifact pattern should stay unchanged"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    TEST_TMP_DIR="$tmp_dir"
    trap 'if [[ -n "${TEST_TMP_DIR:-}" ]]; then rm -rf "$TEST_TMP_DIR"; fi' EXIT

    mkdir -p "$tmp_dir/a" "$tmp_dir/b"
    touch "$tmp_dir/a/luci-app-timecontrol_1_all.ipk"
    touch "$tmp_dir/a/luci-app-timecontrol-zh-cn_1_all.ipk"
    touch "$tmp_dir/b/other_1_all.ipk"

    assert_true "glob patterns should match relative artifact paths" \
        artifact_matches_pattern "a/luci-app-timecontrol_1_all.ipk" "*/luci-app-timecontrol_*.ipk"

    assert_true "basename patterns should match artifact basename" \
        artifact_matches_pattern "a/luci-app-timecontrol-zh-cn_1_all.ipk" "luci-app-timecontrol-zh-cn_*.ipk"

    if artifact_matches_pattern "b/other_1_all.ipk" "*/luci-app-timecontrol_*.ipk"; then
        echo "ASSERT_FALSE failed: unrelated artifacts should not match package glob" >&2
        exit 1
    fi

    echo "build-ipk tests passed"
}

main "$@"
