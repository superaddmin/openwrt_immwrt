# 上游源码管理

> 本文档说明 submodule 源码的初始化、修改、补丁导出、锁定、校验与回滚流程。

## 概述

本项目将 6 个上游 OpenWRT 源码作为 git submodule 纳入 `sources/<source-id>/`。构建时不直接在 submodule 工作树编译,而是通过 [scripts/prepare-source.sh](../scripts/prepare-source.sh) 同步到 `action_build/` 副本,在副本上执行定制与编译。这样既锁定了上游 commit,又保护了 submodule 工作树的干净。

## 源码 submodule 列表

详见 [设备适配 - 源码 submodule 映射](设备适配.md#源码-submodule-映射)。6 个 source:

| source-id | 路径 | 上游 |
|-----------|------|------|
| immortalwrt | sources/immortalwrt | immortalwrt/immortalwrt (master) |
| imm-nss | sources/imm-nss | VIKINGYFY/immortalwrt (main) |
| libwrt | sources/libwrt | LiBwrt/openwrt-6.x (main-nss) |
| libwrt-k612 | sources/libwrt-k612 | LiBwrt/openwrt-6.x (25.12-nss) |
| imm-mt798x | sources/imm-mt798x | padavanonly/immortalwrt-mt798x (openwrt-21.02) |
| airoha-wrt | sources/airoha-wrt | ZqinKing/immortalwrt (w1701k) |

## 初始化 submodule

### 按设备初始化(推荐)

只初始化当前要编译设备需要的那个 submodule,避免拉取全部 6 个源码(每个数百 MB):

```bash
# 查看 device → source-id 映射
grep BUILD_DIR wrt_core/compilecfg/<device>.ini

# 初始化指定 submodule(浅克隆)
git submodule update --init --depth 1 -- sources/<source-id>

# 示例:编译 jdcloud_ipq60xx_immwrt(对应 imm-nss)
git submodule update --init --depth 1 -- sources/imm-nss
```

### 初始化全部

```bash
git submodule update --init --depth 1
```

不推荐:6 个源码总计可能超过 2GB,且多数设备只需其中 1 个。

### CI 中的初始化

GitHub Actions 自动按设备初始化(见 [构建流程 - CI 特有流程](构建流程.md#1-按需初始化-submodule)):

```yaml
- name: Init Target Source Submodule
  run: |
    git submodule sync -- "sources/${SOURCE_ID}"
    git submodule update --init --depth 1 -- "sources/${SOURCE_ID}"
```

## 源码准备(构建副本)

每次构建前,[prepare-source.sh](../scripts/prepare-source.sh) 把 `sources/<source-id>` 同步到 `action_build/`:

```bash
./scripts/prepare-source.sh <device>
```

### 同步规则

- **优先 rsync**:`rsync -a --delete` + 排除项,高效增量同步
- **回退 tar**:无 rsync 时用 tar 管道,且**保留 .ccache 与 staging_dir**(mv 到临时目录,重建后 mv 回)
- **排除项**:`.git`、`.ccache`、`bin`、`build_dir`、`dl`、`logs`、`staging_dir`、`tmp`、`feeds`、`package/feeds`、`.config`、`.config.old`

### 路径断言

[prepare-source.sh#assert_build_copy_path](../scripts/prepare-source.sh) 强制 `build_copy_path == $repo_root/action_build`,防止误操作其他目录。

### 源码锁

同步完成后写入 `action_build/.source-lock`:

```
device=jdcloud_ipq60xx_immwrt
source_path=sources/imm-nss
source_url=https://github.com/VIKINGYFY/immortalwrt.git
source_branch=main
source_commit=a1b2c3d4e5f6...
locked_at_utc=2026-06-30T09:00:00Z
```

确保每次构建可追溯到精确的上游 commit。

## 修改上游源码

### 场景

需要修改上游源码本身(而非通过定制脚本 patch),例如修复上游 bug、调整内核配置等。

### 流程

1. **进入 submodule**:
   ```bash
   cd sources/imm-nss
   ```

2. **在 submodule 内提交修改**:
   ```bash
   git status
   git commit -am "fix: 调整上游源码"
   ```

3. **推送到可访问的 fork/镜像**:
   ```bash
   # 需先添加你的 fork 为 remote(若上游非你账号)
   git remote add myfork https://github.com/<your-account>/immortalwrt.git
   git push myfork main
   ```
   
   **关键**:CI 只能访问已推送到远端的 commit。本地提交未推送,CI 拉取 submodule 时会失败。

4. **回主仓库更新 submodule 指针**:
   ```bash
   cd ../..
   git add sources/imm-nss
   git commit -m "chore: 更新imm-nss源码指针"
   git push
   ```

### 导出工作树差异为 patch

若想保留源码修改作为 patch 存档(便于审查或迁移):

```bash
./scripts/export-source-patches.sh <source-id>
```

[export-source-patches.sh](../scripts/export-source-patches.sh) 会:
- 检查 submodule 已初始化
- `git diff --binary > patches/local/<source-id>/<timestamp>-working-tree.patch`
- 无差异则跳过

patch 存档于 `patches/local/<source-id>/`,不影响构建流程,仅作记录。

## 源码锁定快照

### 写入构建锁(自动)

每次 prepare-source.sh 执行时自动写入 `action_build/.source-lock`(见上文)。

### 批量更新元数据锁(手动)

[update-source-locks.sh](../scripts/update-source-locks.sh) 可为所有(或指定)设备的 source 写入持久化锁文件到 `metadata/sources/<source-id>.lock`:

```bash
# 所有设备
./scripts/update-source-locks.sh

# 指定设备
./scripts/update-source-locks.sh jdcloud_ipq60xx_immwrt x64_immwrt
```

用途:作为源码版本的快照存档,便于审计"某次发布用的是哪个 commit"。

## 源码校验

### validate-source.sh

[validate-source.sh](../scripts/validate-source.sh) 在构建前执行三项校验:

```bash
./scripts/validate-source.sh <device>
```

1. **submodule 注册校验**:设备对应的 `sources/<source-id>` 必须在 `.gitmodules` 中注册
2. **submodule 初始化校验**:`sources/<source-id>/.git` 必须存在(可用 `--skip-submodule-exists` 跳过,仅校验依赖登记)
3. **外部依赖登记校验**:扫描 `wrt_core/*.sh`、`wrt_core/modules/*.sh`、`wrt_core/compilecfg/*.ini` 中所有 `https://` URL,逐一校验是否在 [metadata/external-dependencies.tsv](../metadata/external-dependencies.tsv) 登记

### 外部依赖清单

[metadata/external-dependencies.tsv](../metadata/external-dependencies.tsv) 是 TSV 格式,字段:

| 字段 | 说明 |
|------|------|
| category | 类别:upstream-source / feed / package-feed / package / raw / binary-feed / release-asset / api / runtime-package-source |
| name | 依赖名称 |
| url | 完整 URL |
| branch_or_ref | 分支或 ref |
| owner | 归属:submodule / dynamic |
| file | 关联文件 |
| purpose | 用途说明 |

### 新增外部 URL

在脚本中引入新的 `https://` URL 时,必须同步在 tsv 中登记,否则 validate-source 报错:

```
Unregistered external dependencies:
  https://github.com/xxx/yyy.git
```

登记示例:
```
package	my-new-pkg	https://github.com/xxx/yyy.git	main	dynamic	wrt_core/modules/packages.sh	Add my-new-pkg package
```

## 回滚源码版本

### 回退到旧 commit

```bash
cd sources/<source-id>
git checkout <old-commit>
cd ../..
git add sources/<source-id>
git commit -m "chore: 回退<source-id>到<old-commit>"
```

### 更新到上游最新

```bash
cd sources/<source-id>
git fetch origin
git checkout <branch>
git pull
cd ../..
git add sources/<source-id>
git commit -m "chore: 更新<source-id>到最新"
```

## 回退到动态 clone 模式(兼容)

若 submodule 流程出现问题,可临时回退到旧的动态 clone 模式:

```bash
WRT_USE_DYNAMIC_CLONE=1 ./build.sh <device>
```

此模式下:
- 不调用 prepare-source.sh
- `BUILD_DIR` 保持 ini 值(如 `imm-nss`)
- [clone_repo](../wrt_core/modules/general.sh) 动态 clone 到该目录
- `REPO_URL`/`REPO_BRANCH` 必须可达

仅用于调试,不推荐常规使用(submodule 模式更稳定、可追溯)。

## 常见问题

**Q: clone 仓库后没有 sources/ 内容?**
A: 主仓库只跟踪 submodule 指针,不自动拉取内容。按需初始化:`git submodule update --init --depth 1 -- sources/<source-id>`。

**Q: CI 报 "Source submodule is not initialized"?**
A: CI 会自动初始化目标 submodule。若失败,检查 `.gitmodules` 中该 submodule 的 url 是否可达,以及 ini 的 `BUILD_DIR` 是否与 `.gitmodules` 的 path 匹配。

**Q: 本地改了源码,CI 编译没生效?**
A: CI 只能访问已推送到远端的 submodule commit。本地修改必须先在 submodule 内提交并推送到可访问的 fork/镜像,再更新主仓库的 submodule 指针。

**Q: 如何查看某次构建用的哪个上游 commit?**
A: 查看 `action_build/.source-lock` 文件的 `source_commit` 字段;或查看 `metadata/sources/<source-id>.lock`(若用 update-source-locks.sh 生成过)。

**Q: 多个设备共用一个 source-id,会冲突吗?**
A: 不会。prepare-source.sh 每次把 source 同步到 `action_build/`(覆盖),同一时刻只编译一个设备。不同设备共用同一 source(如多个 IPQ60xx 设备都用 imm-nss)只是共享上游源码,定制差异在 `deconfig/<device>.config` 中体现。
