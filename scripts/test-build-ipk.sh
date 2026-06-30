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

assert_file_contains() {
    local file="$1"
    local expected="$2"
    local message="$3"

    if ! grep -Fxq "$expected" "$file"; then
        echo "ASSERT_FILE_CONTAINS failed: $message" >&2
        echo "  missing line: $expected" >&2
        echo "  file content:" >&2
        sed 's/^/    /' "$file" >&2
        exit 1
    fi
}

test_main_prepares_dependencies_before_compiling() {
    local tmp_dir
    local test_device
    local test_artifact_dir

    tmp_dir=$(mktemp -d)
    test_device="test-ipk-device-$$"
    test_artifact_dir="$REPO_ROOT/ipk_artifacts/$test_device"

    (
        set -euo pipefail

        local log_file="$tmp_dir/calls.log"

        ensure_action_build_ready() {
            echo "ensure_action_build_ready:$1" >>"$log_file"
            mkdir -p "$REPO_ROOT/action_build/bin"
        }

        prepare_build_dependencies() {
            echo "prepare_build_dependencies:$1" >>"$log_file"
        }

        compile_targets() {
            local build_dir="$1"
            shift
            echo "compile_targets:$build_dir:$*" >>"$log_file"
        }

        copy_matching_ipks() {
            local build_dir="$1"
            local artifact_dir="$2"
            local stamp_file="$3"
            shift 3
            echo "copy_matching_ipks:$build_dir:$artifact_dir:$stamp_file:$*" >>"$log_file"
            touch "$artifact_dir/luci-app-timecontrol_1_all.ipk"
        }

        write_metadata_files() {
            echo "write_metadata_files:$*" >>"$log_file"
        }

        WRT_IPK_TARGETS=""
        WRT_IPK_ARTIFACT_PATTERNS="luci-app-timecontrol_*.ipk"
        main "$test_device" luci-app-timecontrol

        assert_file_contains "$log_file" "ensure_action_build_ready:$test_device" \
            "main should prepare action_build first"
        assert_file_contains "$log_file" "prepare_build_dependencies:$REPO_ROOT/action_build" \
            "main should prepare OpenWrt host tools and toolchain before package compile"
        assert_file_contains "$log_file" "compile_targets:$REPO_ROOT/action_build:package/luci-app-timecontrol" \
            "main should compile normalized package targets"

        local sequence
        sequence=$(awk '
            /^prepare_build_dependencies:/ {prepare = NR}
            /^compile_targets:/ {compile = NR}
            END {if (prepare > 0 && compile > 0 && prepare < compile) print "ok"}
        ' "$log_file")

        assert_eq "ok" "$sequence" \
            "OpenWrt build dependencies should be prepared before compiling package targets"
    )

    rm -rf "$tmp_dir"
    rm -rf "$test_artifact_dir"
}

test_prepare_build_dependencies_runs_openwrt_prerequisites() {
    local tmp_dir
    local log_file

    tmp_dir=$(mktemp -d)
    log_file="$tmp_dir/calls.log"

    (
        set -euo pipefail

        nproc() {
            echo 2
        }

        run_openwrt_make() {
            echo "run_openwrt_make:$1:$(pwd)" >>"$log_file"
        }

        prepare_build_dependencies "$tmp_dir"
    )

    assert_file_contains "$log_file" "run_openwrt_make:tools/install:$tmp_dir" \
        "prepare_build_dependencies should install OpenWrt host tools"
    assert_file_contains "$log_file" "run_openwrt_make:toolchain/install:$tmp_dir" \
        "prepare_build_dependencies should install OpenWrt toolchain"
    assert_file_contains "$log_file" "run_openwrt_make:target/compile:$tmp_dir" \
        "prepare_build_dependencies should compile OpenWrt target artifacts"

    local sequence
    sequence=$(awk '
        /run_openwrt_make:tools\/install:/ {tools = NR}
        /run_openwrt_make:toolchain\/install:/ {toolchain = NR}
        /run_openwrt_make:target\/compile:/ {target = NR}
        END {
            if (tools > 0 && toolchain > tools && target > toolchain) {
                print "ok"
            }
        }
    ' "$log_file")

    assert_eq "ok" "$sequence" \
        "OpenWrt target artifacts should be prepared after tools and toolchain"

    rm -rf "$tmp_dir"
}

run_tests() {
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

    test_prepare_build_dependencies_runs_openwrt_prerequisites
    test_main_prepares_dependencies_before_compiling

    echo "build-ipk tests passed"
}

run_tests "$@"
