# GitHub IPK Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为仓库增加“构建并发布独立 `.ipk` 到 GitHub Release”的自动化链路，同时保持现有固件构建与发布流程不受影响。

**Architecture:** 新增 `scripts/build-ipk.sh` 作为独立包构建入口，复用 `./build.sh <device> debug` 产出的 `action_build/` 环境，并新增 `release_ipk.yml` 在 GitHub Actions 中按需初始化目标 submodule、构建指定包、收集 `.ipk` 和发布 Release 附件。

**Tech Stack:** Bash, GitHub Actions YAML, OpenWrt build system, Git submodule, Ubuntu 24.04.

## Global Constraints

- 默认中文说明、文档与变更说明。
- 复用现有 `sources/<source-id>` 与 `action_build/` 机制，不新增第二套源码准备逻辑。
- 不替换现有 `build_wrt.yml` 与 `release_wrt.yml`。
- `ipk_artifacts/` 仅作为临时发布产物目录，必须忽略。
- workflow 默认采用 `workflow_dispatch`，避免误发独立包版本。

---

### Task 1: 设计与计划落库

**Files:**
- Create: `docs/superpowers/specs/2026-06-30-github-ipk-release-design.md`
- Create: `docs/superpowers/plans/2026-06-30-github-ipk-release.md`

**Interfaces:**
- Produces: `.ipk` 发布链路的设计边界、输入输出约定和验证标准。

- [ ] 写入设计文档，明确 Release 附件方案、脚本边界、workflow 输入和产物追踪机制。
- [ ] 写入实施计划，明确脚本、workflow、文档和验证步骤。

### Task 2: 独立包构建脚本

**Files:**
- Create: `scripts/build-ipk.sh`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `scripts/build-ipk.sh <device> [targets...]`
- Produces: `ipk_artifacts/<device>/`

- [ ] 解析 `device`、`WRT_IPK_TARGETS`、`WRT_IPK_ARTIFACT_PATTERNS`
- [ ] 调用 `./build.sh <device> debug`
- [ ] 在 `action_build/` 中执行 `make <target>/download` 与 `make <target>/compile`
- [ ] 收集 `.ipk`、生成 `sha256sums.txt`、复制 `source-lock.txt`
- [ ] 将 `ipk_artifacts/` 加入 `.gitignore`
- [ ] 运行 `bash -n scripts/build-ipk.sh`

### Task 3: GitHub Actions 发布工作流

**Files:**
- Create: `.github/workflows/release_ipk.yml`

**Interfaces:**
- Produces: `Release IPK` workflow
- Consumes: `scripts/validate-source.sh`、`scripts/build-ipk.sh`

- [ ] 增加 `workflow_dispatch` 输入：`model`、`package_targets`、`artifact_patterns`
- [ ] 复用现有 checkout / resolve source / targeted submodule init / cache 逻辑
- [ ] 调用 `scripts/build-ipk.sh`
- [ ] 校验 `ipk_artifacts/<device>/` 存在 `.ipk`
- [ ] 生成 Release 正文并上传附件
- [ ] 运行 `actionlint .github/workflows/release_ipk.yml`

### Task 4: 文档与验证

**Files:**
- Modify: `README.md`
- Modify: `docs/README.md`
- Modify: `docs/构建流程.md`
- Modify: `docs/技术架构.md`
- Create: `docs/ipk-release.md`

**Interfaces:**
- Produces: `.ipk` 构建与发布使用说明

- [ ] 在主 README 增加独立 `.ipk` 发布说明
- [ ] 在 docs 索引增加 `ipk-release.md`
- [ ] 在构建流程文档增加 `scripts/build-ipk.sh` 与 `release_ipk.yml`
- [ ] 在技术架构文档补充 `ipk_artifacts/` 和独立包发布链路
- [ ] 运行 `bash -n` 和 `actionlint` 做最终静态验证

## Final Verification

```bash
git status --short --branch
bash -n scripts/build-ipk.sh scripts/*.sh build.sh wrt_core/update.sh wrt_core/modules/general.sh wrt_core/build_container.sh
actionlint .github/workflows/release_ipk.yml
```

Expected:

- 工作树只包含本次预期改动
- shell 脚本语法通过
- GitHub Actions workflow 语法通过
