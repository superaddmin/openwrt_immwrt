# Upstream Submodule Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 OpenWrt/ImmortalWrt 主源码改为 `sources/` 下的 Git submodule，并让本地构建与 GitHub Actions 使用可追踪的本地源码副本完成构建。

**Architecture:** 主仓库保留 `wrt_core/` 作为定制层；上游主源码通过 `sources/<source-id>` submodule 固定版本；构建时由 `scripts/prepare-source.sh` 同步到 `action_build/`，`wrt_core/update.sh` 在本地源码模式下只执行定制流程，不再 clone/reset 主仓库。CI 只初始化目标设备需要的 submodule，并用源码 commit、配置和脚本 hash 参与缓存与发布摘要。

**Tech Stack:** Bash, Git submodule, OpenWrt build system, GitHub Actions YAML, Ubuntu 24.04, Docker optional build mode.

## Global Constraints

- 默认中文说明、提交信息和文档。
- Windows PowerShell 中读取中文文件必须显式 `-Encoding UTF8`；编辑 UTF-8 文件优先用 `apply_patch`。
- 不把 OpenWrt/ImmortalWrt 完整源码作为普通文件 vendor 到主仓库。
- 不提交 `action_build/`、`firmware/`、`bin/`、`build_dir/`、`staging_dir/`、`tmp/`、`dl/`、`.ccache/` 等构建产物。
- `sources/` 只放主源码 submodule；第三方动态来源先登记到 `metadata/external-dependencies.tsv`。
- GitHub Actions 不递归初始化全部 submodule，只初始化输入设备对应的 `sources/<BUILD_DIR>`。
- `wrt_core/pre_clone_action.sh` 保留为动态 clone 回滚入口，不作为默认 CI 路径。
- 如果 submodule 指向本机未推送 commit，CI 预期失败；文档必须说明需要推送 fork 或镜像。

---

## File Structure

- Create `.gitmodules`: 记录 6 个主源码 submodule 的路径、URL 和分支。
- Create `.gitattributes`: 固定 shell、YAML、Markdown、TSV 和 Git 配置文件为 LF，避免 Windows 检出导致脚本换行漂移。
- Add submodule gitlinks: 通过 `git submodule add` 生成 `sources/<source-id>` gitlink，确保 CI 能执行 targeted submodule init。
- Create `scripts/source-common.sh`: 共享函数，解析设备 ini、解析源码目录、输出源码 commit、写 lock。
- Create `scripts/validate-source.sh`: 校验设备配置、submodule 路径、依赖清单与脚本中 clone URL。
- Create `scripts/prepare-source.sh`: 从 `sources/<BUILD_DIR>` 同步构建副本到 `action_build/`。
- Create `scripts/export-source-patches.sh`: 导出 submodule 工作区差异到 `patches/local/<source-id>/`。
- Create `scripts/update-source-locks.sh`: 显式更新 `metadata/sources/*.lock`。
- Create `metadata/external-dependencies.tsv`: 登记现有第三方 clone/curl/wget 依赖。
- Modify `.gitignore`: 忽略 `action_build/`、`sources/*` 中构建产物、`patches/local/**/*.tmp` 等必要路径，不忽略 submodule 指针。
- Modify `wrt_core/update.sh`: 支持 `WRT_LOCAL_SOURCE=1` 时跳过 `clone_repo` 和 `reset_feeds_conf`。
- Modify `wrt_core/modules/general.sh`: 拆分 `reset_feeds_conf` 为可跳过的 Git 重置步骤与普通清理步骤。
- Modify `build.sh`: 调用 `scripts/prepare-source.sh`，使用 `action_build` 作为默认构建副本。
- Modify `wrt_core/build_container.sh`: 确认容器内调用仍走同一 `build.sh` 路径。
- Modify `.github/workflows/build_wrt.yml`: 目标 submodule 初始化、源码校验、缓存 key、产物验证、artifact 上传。
- Modify `.github/workflows/release_wrt.yml`: 同步 build workflow 的源码准备逻辑，并把源码 commit 写入 release body。
- Modify `README.md`: 更新项目结构、克隆方式、submodule 初始化、本地源码修改和 CI 触发说明。
- Create `docs/source-management.md`: 说明 submodule 修改、推送、锁定、补丁导出和回滚流程。

---

### Task 1: Submodule Skeleton And Ignore Boundaries

**Files:**
- Create: `.gitmodules`
- Create: `.gitattributes`
- Add submodule gitlinks: `sources/immortalwrt`, `sources/imm-nss`, `sources/libwrt`, `sources/libwrt-k612`, `sources/imm-mt798x`, `sources/airoha-wrt`
- Modify: `.gitignore`
- Test: shell commands only

**Interfaces:**
- Produces: `sources/<source-id>` path contract consumed by `scripts/source-common.sh`.
- Produces: `.gitmodules` entries consumed by GitHub Actions targeted submodule init.

- [ ] **Step 1: Record current state**

Run:

```powershell
git status --short --branch
```

Expected: no unrelated uncommitted files except the current task files after edits begin.

- [ ] **Step 2: Add line-ending rules**

Create `.gitattributes` with exact content:

```gitattributes
*.md text eol=lf
*.sh text eol=lf
*.yml text eol=lf
*.yaml text eol=lf
*.tsv text eol=lf
.gitmodules text eol=lf
.gitattributes text eol=lf
```

- [ ] **Step 3: Add upstream source submodules**

Run:

```powershell
git submodule add --depth 1 -b master https://github.com/immortalwrt/immortalwrt.git sources/immortalwrt
git submodule add --depth 1 -b main https://github.com/VIKINGYFY/immortalwrt.git sources/imm-nss
git submodule add --depth 1 -b main-nss https://github.com/LiBwrt/openwrt-6.x.git sources/libwrt
git submodule add --depth 1 -b k6.12-nss https://github.com/LiBwrt/openwrt-6.x.git sources/libwrt-k612
git submodule add --depth 1 -b openwrt-21.02 https://github.com/padavanonly/immortalwrt-mt798x.git sources/imm-mt798x
git submodule add --depth 1 -b w1701k https://github.com/ZqinKing/immortalwrt.git sources/airoha-wrt
```

Expected: each command creates a gitlink under `sources/` and updates `.gitmodules`.

- [ ] **Step 4: Update `.gitignore`**

Append these entries if missing:

```gitignore
action_build/
metadata/sources/*.runtime.lock
patches/local/**/*.tmp
sources/*/.ccache/
sources/*/bin/
sources/*/build_dir/
sources/*/dl/
sources/*/logs/
sources/*/staging_dir/
sources/*/tmp/
```

Do not add `sources/` or `sources/*` as a blanket ignore, because Git must track submodule gitlinks.

- [ ] **Step 5: Validate submodule config syntax**

Run:

```powershell
git config --file .gitmodules --get-regexp '^submodule\..*\.(path|url|branch)$'
```

Expected: 18 lines, three fields for each of the 6 source submodules.

- [ ] **Step 6: Validate gitlinks exist**

Run:

```powershell
git ls-files --stage sources
```

Expected: six entries with mode `160000`, one for each source submodule.

- [ ] **Step 6: Commit**

Run:

```powershell
git add .gitattributes .gitmodules .gitignore sources/immortalwrt sources/imm-nss sources/libwrt sources/libwrt-k612 sources/imm-mt798x sources/airoha-wrt
git commit -m "chore: 声明上游源码submodule边界"
```

Expected: commit succeeds.

---

### Task 2: Source Metadata And Dependency Validation Scripts

**Files:**
- Create: `scripts/source-common.sh`
- Create: `scripts/validate-source.sh`
- Create: `metadata/external-dependencies.tsv`
- Create: `metadata/sources/.gitkeep`
- Test: `bash scripts/validate-source.sh x64_immwrt --skip-submodule-exists`

**Interfaces:**
- Produces function `read_ini_value <ini-file> <key>` returning raw value.
- Produces function `resolve_device_source <device>` exporting `DEVICE`, `INI_FILE`, `CONFIG_FILE`, `SOURCE_ID`, `SOURCE_PATH`, `REPO_URL`, `REPO_BRANCH`, `COMMIT_HASH`.
- Produces function `source_commit <source-path>` printing `git -C <source-path> rev-parse HEAD`.
- Produces command `scripts/validate-source.sh <device> [--skip-submodule-exists]`.
- Consumes `.gitmodules` and `wrt_core/compilecfg/*.ini` from Task 1.

- [ ] **Step 1: Create `metadata/external-dependencies.tsv`**

Create the file with this header and rows:

```tsv
name	type	url	ref	target	allow_dynamic
openwrt_bandix	feed	https://github.com/timsaya/openwrt-bandix.git	main	feeds.conf.default	true
luci_app_bandix	feed	https://github.com/timsaya/luci-app-bandix.git	main	feeds.conf.default	true
small-package	custom-feed	https://github.com/kenzok8/small-package.git	default	custom_feed/packages	true
luci-app-mosdns	custom-feed	https://github.com/sbwml/luci-app-mosdns.git	v5	custom_feed/packages	true
openwrt-passwall	custom-feed	https://github.com/Openwrt-Passwall/openwrt-passwall.git	main	custom_feed/packages	true
openwrt-nikki	custom-feed	https://github.com/nikkinikki-org/OpenWrt-nikki.git	main	custom_feed/packages	true
immortalwrt-default-settings	package-source	https://github.com/immortalwrt/immortalwrt.git	default	package/emortal/default-settings	true
luci-app-athena-led	package	https://github.com/NONGFAH/luci-app-athena-led.git	default	package/emortal/luci-app-athena-led	true
homeproxy	package	https://github.com/immortalwrt/homeproxy.git	default	feeds/luci/applications/homeproxy	true
luci-app-timecontrol	package	https://github.com/sirpdboy/luci-app-timecontrol.git	default	package/luci-app-timecontrol	true
luci-app-adguardhome	package	https://github.com/ZqinKing/luci-app-adguardhome.git	default	package/luci-app-adguardhome	true
luci-app-lucky	package	https://github.com/gdy666/luci-app-lucky.git	default	package/luci-app-lucky	true
openwrt-smartdns	package	https://github.com/ZqinKing/openwrt-smartdns.git	default	feeds/packages/net/smartdns	true
luci-app-smartdns	package	https://github.com/pymumu/luci-app-smartdns.git	default	feeds/luci/applications/luci-app-smartdns	true
luci-app-diskman	package	https://github.com/lisaac/luci-app-diskman.git	default	feeds/luci/applications/luci-app-diskman	true
luci-lib-docker	package	https://github.com/lisaac/luci-lib-docker.git	default	feeds/luci/libs/luci-lib-docker	true
luci-app-dockerman	package	https://github.com/lisaac/luci-app-dockerman.git	default	feeds/luci/applications/luci-app-dockerman	true
luci-app-quickfile	package	https://github.com/sbwml/luci-app-quickfile.git	default	package/emortal/quickfile	true
luci-theme-argon	theme	https://github.com/ZqinKing/luci-theme-argon.git	default	feeds/luci/themes/luci-theme-argon	true
packages-lang-golang	package	https://github.com/sbwml/packages_lang_golang	26.x	feeds/packages/lang/golang	true
ath11k-firmware-makefile	raw	https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/refs/heads/main/package/firmware/ath11k-firmware/Makefile	main	package/firmware/ath11k-firmware/Makefile	true
passwall-tcping-makefile	raw	https://raw.githubusercontent.com/Openwrt-Passwall/openwrt-passwall-packages/refs/heads/main/tcping/Makefile	main	package/feeds/packages/tcping/Makefile	true
istore-backend	raw	https://gist.githubusercontent.com/puteulanus/1c180fae6bccd25e57eb6d30b7aa28aa/raw/istore_backend.lua	default	feeds/luci/applications/luci-app-store/root/usr/share/istore/istore_backend.lua	true
geoip-release	release	https://github.com/v2fly/geoip	latest	feeds/packages/net/v2ray-geodata	true
quectel-cm-source	package-source	https://github.com/Carton32/quectel-CM.git	default	package/feeds/packages/quectel-cm	true
```

- [ ] **Step 2: Create `metadata/sources/.gitkeep`**

Create `metadata/sources/.gitkeep` with exact content:

```text
# Source lock files generated by scripts/update-source-locks.sh live here.
```

- [ ] **Step 3: Create `scripts/source-common.sh`**

Create executable Bash file:

```bash
#!/usr/bin/env bash

set -euo pipefail

source_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null || pwd
}

read_ini_value() {
    local ini_file=$1
    local key=$2
    awk -F'=' -v key="$key" '$1 == key {print $2; exit}' "$ini_file"
}

resolve_device_source() {
    local device=$1
    REPO_ROOT=$(source_repo_root)
    DEVICE=$device
    INI_FILE="$REPO_ROOT/wrt_core/compilecfg/$DEVICE.ini"
    CONFIG_FILE="$REPO_ROOT/wrt_core/deconfig/$DEVICE.config"

    if [[ ! -f "$INI_FILE" ]]; then
        echo "INI file not found: $INI_FILE" >&2
        return 1
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Config file not found: $CONFIG_FILE" >&2
        return 1
    fi

    REPO_URL=$(read_ini_value "$INI_FILE" "REPO_URL")
    REPO_BRANCH=$(read_ini_value "$INI_FILE" "REPO_BRANCH")
    SOURCE_ID=$(read_ini_value "$INI_FILE" "BUILD_DIR")
    COMMIT_HASH=$(read_ini_value "$INI_FILE" "COMMIT_HASH")
    REPO_BRANCH=${REPO_BRANCH:-main}
    COMMIT_HASH=${COMMIT_HASH:-none}

    if [[ -z "$REPO_URL" || -z "$SOURCE_ID" ]]; then
        echo "REPO_URL and BUILD_DIR are required in $INI_FILE" >&2
        return 1
    fi

    SOURCE_PATH="$REPO_ROOT/sources/$SOURCE_ID"
    BUILD_COPY_PATH="$REPO_ROOT/action_build"

    export REPO_ROOT DEVICE INI_FILE CONFIG_FILE REPO_URL REPO_BRANCH SOURCE_ID COMMIT_HASH SOURCE_PATH BUILD_COPY_PATH
}

source_commit() {
    local source_path=$1
    git -C "$source_path" rev-parse HEAD
}

source_remote_url() {
    local source_path=$1
    git -C "$source_path" config --get remote.origin.url
}

write_source_lock() {
    local lock_path=$1
    local source_path=$2
    mkdir -p "$(dirname "$lock_path")"
    {
        echo "device=$DEVICE"
        echo "source_id=$SOURCE_ID"
        echo "source_path=$source_path"
        echo "repo_url=$REPO_URL"
        echo "repo_branch=$REPO_BRANCH"
        echo "commit=$(source_commit "$source_path")"
        echo "remote=$(source_remote_url "$source_path")"
    } >"$lock_path"
}
```

- [ ] **Step 4: Create `scripts/validate-source.sh`**

Create executable Bash file:

```bash
#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=source-common.sh
source "$SCRIPT_DIR/source-common.sh"

usage() {
    echo "Usage: $0 <device> [--skip-submodule-exists]"
}

if [[ $# -lt 1 ]]; then
    usage >&2
    exit 1
fi

DEVICE_ARG=$1
SKIP_SUBMODULE_EXISTS=0
if [[ ${2:-} == "--skip-submodule-exists" ]]; then
    SKIP_SUBMODULE_EXISTS=1
fi

resolve_device_source "$DEVICE_ARG"

if ! git config --file "$REPO_ROOT/.gitmodules" --get-regexp '^submodule\..*\.path$' | awk '{print $2}' | grep -qx "sources/$SOURCE_ID"; then
    echo "Missing .gitmodules entry for sources/$SOURCE_ID" >&2
    exit 1
fi

if [[ $SKIP_SUBMODULE_EXISTS -eq 0 ]]; then
    if [[ ! -d "$SOURCE_PATH/.git" && ! -f "$SOURCE_PATH/.git" ]]; then
        echo "Source submodule is not initialized: $SOURCE_PATH" >&2
        exit 1
    fi
    write_source_lock "$REPO_ROOT/action_build/.source-lock" "$SOURCE_PATH"
    cat "$REPO_ROOT/action_build/.source-lock"
fi

if [[ ! -f "$REPO_ROOT/metadata/external-dependencies.tsv" ]]; then
    echo "Missing metadata/external-dependencies.tsv" >&2
    exit 1
fi

script_urls=$(grep -RhoE \"https://[^\\\"'[:space:]\\\\]+\" \"$REPO_ROOT/wrt_core\" | sed 's/[);,]$//' | sort -u)
missing_urls=0
while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    case "$url" in
        https://github.com/*|https://raw.githubusercontent.com/*|https://gist.githubusercontent.com/*)
            if ! grep -Fq "$url" "$REPO_ROOT/metadata/external-dependencies.tsv" && ! grep -Fq "$url" "$REPO_ROOT/.gitmodules"; then
                echo "Unregistered external dependency: $url" >&2
                missing_urls=1
            fi
            ;;
    esac
done <<<"$script_urls"

if [[ $missing_urls -ne 0 ]]; then
    exit 1
fi

echo "Source validation passed for $DEVICE_ARG -> sources/$SOURCE_ID"
```

- [ ] **Step 5: Make scripts executable**

Run:

```powershell
git update-index --chmod=+x scripts/source-common.sh scripts/validate-source.sh
```

Expected: no output.

- [ ] **Step 6: Run validation without initialized submodule**

Run:

```powershell
bash scripts/validate-source.sh x64_immwrt --skip-submodule-exists
```

Expected: `Source validation passed for x64_immwrt -> sources/immortalwrt`.

- [ ] **Step 7: Commit**

Run:

```powershell
git add scripts/source-common.sh scripts/validate-source.sh metadata/external-dependencies.tsv metadata/sources/.gitkeep
git commit -m "feat: 添加源码校验与外部依赖清单"
```

Expected: commit succeeds.

---

### Task 3: Source Preparation And Tracking Utilities

**Files:**
- Create: `scripts/prepare-source.sh`
- Create: `scripts/export-source-patches.sh`
- Create: `scripts/update-source-locks.sh`
- Modify: `scripts/source-common.sh`
- Test: `bash scripts/prepare-source.sh x64_immwrt --dry-run`

**Interfaces:**
- Produces command `scripts/prepare-source.sh <device> [--dry-run]`.
- Produces command `scripts/export-source-patches.sh <source-id>`.
- Produces command `scripts/update-source-locks.sh [device ...]`.
- Consumes functions from `scripts/source-common.sh`.
- Produces `action_build/.source-lock` when source exists.

- [ ] **Step 1: Extend `source-common.sh` with sync excludes**

Append:

```bash
source_sync_excludes() {
    cat <<'EOF'
.git
.ccache
bin
build_dir
dl
logs
staging_dir
tmp
feeds
package/feeds
.config
.config.old
EOF
}
```

- [ ] **Step 2: Create `scripts/prepare-source.sh`**

Create executable Bash file:

```bash
#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=source-common.sh
source "$SCRIPT_DIR/source-common.sh"

usage() {
    echo "Usage: $0 <device> [--dry-run]"
}

if [[ $# -lt 1 ]]; then
    usage >&2
    exit 1
fi

DEVICE_ARG=$1
DRY_RUN=0
if [[ ${2:-} == "--dry-run" ]]; then
    DRY_RUN=1
fi

resolve_device_source "$DEVICE_ARG"

if [[ ! -d "$SOURCE_PATH/.git" && ! -f "$SOURCE_PATH/.git" ]]; then
    echo "Source submodule is not initialized: $SOURCE_PATH" >&2
    echo "Run: git submodule update --init --depth 1 sources/$SOURCE_ID" >&2
    exit 1
fi

if [[ $DRY_RUN -eq 1 ]]; then
    echo "Would prepare $BUILD_COPY_PATH from $SOURCE_PATH"
    source_sync_excludes | sed 's/^/exclude: /'
    exit 0
fi

rm -rf "$BUILD_COPY_PATH"
mkdir -p "$BUILD_COPY_PATH"

if command -v rsync >/dev/null 2>&1; then
    mapfile -t excludes < <(source_sync_excludes)
    rsync_args=(-a --delete)
    for item in "${excludes[@]}"; do
        rsync_args+=(--exclude "$item")
    done
    rsync "${rsync_args[@]}" "$SOURCE_PATH/" "$BUILD_COPY_PATH/"
else
    tar --exclude='.git' --exclude='.ccache' --exclude='bin' --exclude='build_dir' --exclude='dl' --exclude='logs' --exclude='staging_dir' --exclude='tmp' --exclude='feeds' --exclude='package/feeds' --exclude='.config' --exclude='.config.old' -C "$SOURCE_PATH" -cf - . | tar -C "$BUILD_COPY_PATH" -xf -
fi

write_source_lock "$BUILD_COPY_PATH/.source-lock" "$SOURCE_PATH"
echo "Prepared $BUILD_COPY_PATH from $SOURCE_PATH"
cat "$BUILD_COPY_PATH/.source-lock"
```

- [ ] **Step 3: Create `scripts/export-source-patches.sh`**

Create executable Bash file:

```bash
#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=source-common.sh
source "$SCRIPT_DIR/source-common.sh"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <source-id>" >&2
    exit 1
fi

SOURCE_ID=$1
REPO_ROOT=$(source_repo_root)
SOURCE_PATH="$REPO_ROOT/sources/$SOURCE_ID"
PATCH_DIR="$REPO_ROOT/patches/local/$SOURCE_ID"

if [[ ! -d "$SOURCE_PATH/.git" && ! -f "$SOURCE_PATH/.git" ]]; then
    echo "Source submodule is not initialized: $SOURCE_PATH" >&2
    exit 1
fi

mkdir -p "$PATCH_DIR"
PATCH_FILE="$PATCH_DIR/$(date -u +%Y%m%d%H%M%S)-working-tree.patch"

git -C "$SOURCE_PATH" diff --binary >"$PATCH_FILE"

if [[ ! -s "$PATCH_FILE" ]]; then
    rm -f "$PATCH_FILE"
    echo "No working tree changes in $SOURCE_ID"
    exit 0
fi

echo "Exported patch: $PATCH_FILE"
```

- [ ] **Step 4: Create `scripts/update-source-locks.sh`**

Create executable Bash file:

```bash
#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=source-common.sh
source "$SCRIPT_DIR/source-common.sh"

REPO_ROOT=$(source_repo_root)

if [[ $# -eq 0 ]]; then
    mapfile -t devices < <(find "$REPO_ROOT/wrt_core/compilecfg" -name '*.ini' -exec basename {} .ini \; | sort)
else
    devices=("$@")
fi

seen=()
for device in "${devices[@]}"; do
    resolve_device_source "$device"
    skip=0
    for existing in "${seen[@]}"; do
        if [[ "$existing" == "$SOURCE_ID" ]]; then
            skip=1
            break
        fi
    done
    [[ $skip -eq 1 ]] && continue
    seen+=("$SOURCE_ID")

    if [[ ! -d "$SOURCE_PATH/.git" && ! -f "$SOURCE_PATH/.git" ]]; then
        echo "Skipping uninitialized source: $SOURCE_ID" >&2
        continue
    fi

    write_source_lock "$REPO_ROOT/metadata/sources/$SOURCE_ID.lock" "$SOURCE_PATH"
    echo "Updated metadata/sources/$SOURCE_ID.lock"
done
```

- [ ] **Step 5: Make scripts executable**

Run:

```powershell
git update-index --chmod=+x scripts/prepare-source.sh scripts/export-source-patches.sh scripts/update-source-locks.sh
```

Expected: no output.

- [ ] **Step 6: Run dry-run validation**

Run:

```powershell
bash scripts/prepare-source.sh x64_immwrt --dry-run
```

Expected when submodule is not initialized: fails with `Source submodule is not initialized`. This is acceptable before Task 4 initializes submodules. After initializing `sources/immortalwrt`, expected output starts with `Would prepare`.

- [ ] **Step 7: Commit**

Run:

```powershell
git add scripts/source-common.sh scripts/prepare-source.sh scripts/export-source-patches.sh scripts/update-source-locks.sh
git commit -m "feat: 添加本地源码准备与追踪脚本"
```

Expected: commit succeeds.

---

### Task 4: Build Script Local Source Mode

**Files:**
- Modify: `wrt_core/modules/general.sh`
- Modify: `wrt_core/update.sh`
- Modify: `build.sh`
- Modify: `wrt_core/build_container.sh`
- Test: `bash -n build.sh wrt_core/update.sh wrt_core/modules/general.sh wrt_core/build_container.sh`

**Interfaces:**
- Consumes `scripts/prepare-source.sh <device>` from Task 3.
- Produces environment variable `WRT_LOCAL_SOURCE=1` for `wrt_core/update.sh`.
- Preserves command `./build.sh <device> [debug|container|container_debug]`.
- Preserves dynamic clone fallback when `WRT_USE_DYNAMIC_CLONE=1` is set.

- [ ] **Step 1: Update `wrt_core/modules/general.sh`**

Change `clone_repo` and `reset_feeds_conf` to respect local source mode:

```bash
clone_repo() {
    if [[ ${WRT_LOCAL_SOURCE:-0} == "1" ]]; then
        if [[ ! -d $BUILD_DIR ]]; then
            echo "Build directory $BUILD_DIR does not exist in local source mode" >&2
            exit 1
        fi
        echo "Using prepared local source tree: $BUILD_DIR"
        return
    fi

    if [[ ! -d $BUILD_DIR ]]; then
        echo "克隆仓库: $REPO_URL 分支: $REPO_BRANCH"
        if ! git_retry clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$BUILD_DIR"; then
            echo "错误：克隆仓库 $REPO_URL 失败" >&2
            exit 1
        fi
    fi
}
```

Replace `reset_feeds_conf` with:

```bash
reset_feeds_conf() {
    if [[ ${WRT_LOCAL_SOURCE:-0} == "1" ]]; then
        echo "Skipping git reset/pull in local source mode"
        return
    fi

    git_retry reset --hard "origin/$REPO_BRANCH"
    git_retry clean -f -d
    git_retry pull
    if [[ $COMMIT_HASH != "none" ]]; then
        git_retry checkout "$COMMIT_HASH"
    fi
}
```

- [ ] **Step 2: Update `wrt_core/update.sh` comments and call flow**

Keep the main sequence, but ensure it remains:

```bash
main() {
    clone_repo
    clean_up
    reset_feeds_conf
    update_feeds
    ...
}
```

No behavior changes beyond Task 4 Step 1. Add a short comment above `main`:

```bash
# In WRT_LOCAL_SOURCE=1 mode, clone_repo/reset_feeds_conf are no-ops against the prepared build copy.
```

- [ ] **Step 3: Update `build.sh` to prepare local source before update**

After reading `BUILD_DIR` from ini and before calling `update.sh`, replace the current `if [[ -d action_build ]]; then BUILD_DIR="action_build"; fi` behavior with:

```bash
SOURCE_BUILD_DIR=$BUILD_DIR

if [[ ${WRT_USE_DYNAMIC_CLONE:-0} == "1" ]]; then
    echo "Using dynamic clone mode for $Dev"
else
    "$REPO_ROOT/scripts/prepare-source.sh" "$Dev"
    BUILD_DIR="action_build"
    export WRT_LOCAL_SOURCE=1
fi
```

Ensure all later paths continue to use `BUILD_DIR=action_build` for prepared builds.

- [ ] **Step 4: Preserve container mode**

In `prepare_container_image`, add `rsync` to apt dependencies because `prepare-source.sh` prefers rsync:

```bash
RUN apt-get update && apt-get install -y sudo git jq rsync build-essential cmake g++ clang bison flex libelf-dev libncurses5-dev python3-distutils zlib1g-dev python3 pkg-config libssl-dev
```

- [ ] **Step 5: Syntax check shell scripts**

Run:

```powershell
bash -n build.sh wrt_core/update.sh wrt_core/modules/general.sh wrt_core/build_container.sh scripts/source-common.sh scripts/prepare-source.sh scripts/validate-source.sh
```

Expected: no output.

- [ ] **Step 6: Validate dynamic fallback still parses**

Run:

```powershell
$env:WRT_USE_DYNAMIC_CLONE='1'; bash build.sh x64_immwrt debug; Remove-Item Env:WRT_USE_DYNAMIC_CLONE
```

Expected: on a machine without full Linux build environment this may fail after clone/setup, but it must not fail with Bash syntax errors or missing `prepare-source.sh`. If it begins dynamic clone/update, stop and record the first environment blocker instead of continuing a full build.

- [ ] **Step 7: Commit**

Run:

```powershell
git add build.sh wrt_core/update.sh wrt_core/modules/general.sh wrt_core/build_container.sh
git commit -m "feat: 构建流程支持本地submodule源码"
```

Expected: commit succeeds.

---

### Task 5: GitHub Actions And Documentation

**Files:**
- Modify: `.github/workflows/build_wrt.yml`
- Modify: `.github/workflows/release_wrt.yml`
- Modify: `README.md`
- Create: `docs/source-management.md`
- Test: YAML grep/static checks and shell syntax checks

**Interfaces:**
- Consumes `scripts/validate-source.sh` and `scripts/prepare-source.sh`.
- Produces workflow env `SOURCE_ID`, `SOURCE_COMMIT`, `SOURCE_LOCK`.
- Preserves workflow_dispatch input `model`.

- [ ] **Step 1: Update checkout and targeted submodule init in `build_wrt.yml`**

Replace checkout step with:

```yaml
      - name: Checkout
        uses: actions/checkout@v7.0.0
        with:
          submodules: false
          fetch-depth: 1
```

Add after timezone step:

```yaml
      - name: Resolve Source
        id: source
        shell: bash
        run: |
          ini="./wrt_core/compilecfg/${{ inputs.model }}.ini"
          source_id=$(awk -F"=" '$1 == "BUILD_DIR" {print $2; exit}' "$ini")
          echo "SOURCE_ID=$source_id" >> "$GITHUB_ENV"
          echo "source_id=$source_id" >> "$GITHUB_OUTPUT"

      - name: Init Target Source Submodule
        run: |
          git submodule sync -- sources/${{ steps.source.outputs.source_id }}
          git submodule update --init --depth 1 -- sources/${{ steps.source.outputs.source_id }}

      - name: Validate Source
        run: ./scripts/validate-source.sh ${{ inputs.model }}
```

Remove the old `Pre Clone` step.

- [ ] **Step 2: Update cache key in `build_wrt.yml`**

Before cache step add:

```yaml
      - name: Export Source Commit
        run: |
          source_commit=$(git -C "sources/${SOURCE_ID}" rev-parse HEAD)
          echo "SOURCE_COMMIT=$source_commit" >> "$GITHUB_ENV"
```

Change cache key to:

```yaml
          key: ${{ matrix.os }}-${{ inputs.model }}-${{ env.SOURCE_COMMIT }}-${{ hashFiles('wrt_core/**/*.sh', 'wrt_core/compilecfg/*.ini', 'wrt_core/deconfig/*.config', 'metadata/external-dependencies.tsv') }}-${{ env.BUILD_DATE }}
          restore-keys: |
            ${{ matrix.os }}-${{ inputs.model }}-${{ env.SOURCE_COMMIT }}-
```

Update cache delete prefix to use the same restore prefix.

- [ ] **Step 3: Add build output validation in `build_wrt.yml`**

Add after `Build Firmware`:

```yaml
      - name: Validate Firmware Output
        run: |
          test -d ./firmware
          count=$(find ./firmware -type f \( -name "*.manifest" -o -name "*.bin" -o -name "*.img.gz" -o -name "*.itb" -o -name "*.ubi" -o -name "*rootfs.tar.gz" \) | wc -l)
          echo "Firmware output count: $count"
          test "$count" -gt 0
```

- [ ] **Step 4: Mirror workflow changes into `release_wrt.yml`**

Apply the same checkout, resolve source, target submodule init, validate source, source commit export and cache key changes. In `Prepare Release Body`, add:

```bash
echo "源码Commit：${{ env.SOURCE_COMMIT }}" >> release_body.txt
```

- [ ] **Step 5: Update `README.md`**

Update these sections:

```markdown
### 2. 克隆仓库

```bash
git clone https://github.com/superaddmin/openwrt_immwrt.git
cd openwrt_immwrt
# 只初始化当前要编译设备需要的源码，例如 x64_immwrt 使用 sources/immortalwrt
git submodule update --init --depth 1 sources/immortalwrt
```

### 本地源码修改

上游主源码位于 `sources/<source-id>`。修改源码后，需要在对应 submodule 仓库内提交并推送到可被 GitHub Actions 访问的 fork 或镜像，然后在主仓库提交 submodule 指针。

```bash
cd sources/immortalwrt
git status
git commit -am "fix: 调整上游源码"
git push
cd ../..
git add sources/immortalwrt
git commit -m "chore: 更新immortalwrt源码指针"
```

构建脚本默认使用本地 submodule 源码同步到 `action_build/` 后编译。如需临时恢复旧的动态 clone 流程，可设置：

```bash
WRT_USE_DYNAMIC_CLONE=1 ./build.sh x64_immwrt debug
```
```

Also update project structure to include `sources/`, `scripts/`, `metadata/`, and `docs/source-management.md`.

- [ ] **Step 6: Create `docs/source-management.md`**

Create concise Chinese documentation with these sections:

```markdown
# 上游源码管理

## 目录

- `sources/<source-id>`：上游主源码 submodule。
- `action_build/`：构建副本，脚本自动生成，不提交。
- `metadata/external-dependencies.tsv`：第三方动态依赖清单。
- `patches/local/<source-id>/`：导出的本地源码差异补丁。

## 初始化单个设备源码

```bash
source_id=$(awk -F= '$1 == "BUILD_DIR" {print $2; exit}' wrt_core/compilecfg/x64_immwrt.ini)
git submodule update --init --depth 1 "sources/$source_id"
```

## 修改和提交上游源码

在 submodule 内提交并推送到 fork，然后回到主仓库提交 submodule 指针。

## 导出补丁

```bash
./scripts/export-source-patches.sh immortalwrt
```

## 更新锁定信息

```bash
./scripts/update-source-locks.sh x64_immwrt
```

## 回滚动态 clone 模式

```bash
WRT_USE_DYNAMIC_CLONE=1 ./build.sh x64_immwrt debug
```
```

- [ ] **Step 7: Static verification**

Run:

```powershell
bash -n scripts/*.sh build.sh wrt_core/update.sh wrt_core/modules/general.sh wrt_core/build_container.sh
Select-String -Path .github\workflows\build_wrt.yml,.github\workflows\release_wrt.yml -Pattern 'Pre Clone|repo_flag|submodules: recursive'
Select-String -Path .github\workflows\build_wrt.yml,.github\workflows\release_wrt.yml -Pattern 'Validate Source|Init Target Source Submodule|SOURCE_COMMIT'
```

Expected: first command no output; second command no matches; third command shows the new workflow steps.

- [ ] **Step 8: Commit**

Run:

```powershell
git add .github/workflows/build_wrt.yml .github/workflows/release_wrt.yml README.md docs/source-management.md
git commit -m "ci: 使用本地submodule源码构建固件"
```

Expected: commit succeeds.

---

## Final Verification

Run after all tasks:

```powershell
git status --short --branch
bash -n scripts/*.sh build.sh wrt_core/update.sh wrt_core/modules/general.sh wrt_core/build_container.sh
bash scripts/validate-source.sh x64_immwrt --skip-submodule-exists
git config --file .gitmodules --get-regexp '^submodule\..*\.(path|url|branch)$'
```

Expected:

- Worktree clean except intentionally uninitialized submodule directories.
- Bash syntax checks pass.
- Validation passes when submodule existence is skipped.
- `.gitmodules` prints 18 lines.

Optional full validation on Linux/WSL after initializing `sources/immortalwrt`:

```bash
git submodule update --init --depth 1 sources/immortalwrt
./scripts/validate-source.sh x64_immwrt
./scripts/prepare-source.sh x64_immwrt
./build.sh x64_immwrt debug
```

Expected: `make defconfig` completes or reports the first real OpenWrt dependency/config blocker.

## Self-Review Notes

- Spec coverage: plan covers submodule mapping, dependency inventory, source validation, build-copy preparation, update/build script local-source mode, CI targeted submodule init, artifact validation, release body source commit, documentation and rollback.
- Marker scan: no TBD/TODO markers are present.
- Type and interface consistency: `SOURCE_ID`, `SOURCE_PATH`, `BUILD_COPY_PATH`, `WRT_LOCAL_SOURCE`, and `WRT_USE_DYNAMIC_CLONE` are consistently named across tasks.
