# 上游源码 Submodule 整合设计

## 背景

当前仓库通过 `wrt_core/compilecfg/*.ini` 描述设备构建来源，并在构建时从上游 OpenWrt/ImmortalWrt 仓库动态 clone 到 `action_build/` 或设备声明的 `BUILD_DIR`。这种模式适合纯自动化编译，但不利于在本地直接修改上游源码、重构源码文件、审查变更和固定可复现版本。

本设计采用 Git submodule 方式整合上游源码，把上游源码固定在 `sources/` 下，并保留 `wrt_core/` 作为本项目定制层。构建时使用源码副本而不是直接污染 submodule 工作区。

## 目标

- 在本地项目中建立清晰的上游源码目录，支持直接修改、重构和编译。
- 通过 submodule commit 指针锁定上游源码版本，形成可审查的版本控制边界。
- 将上游源码、本项目构建脚本、本地补丁和构建产物隔离。
- 改造本地构建脚本和 GitHub Actions，使它们优先使用本地 submodule 源码。
- 建立第三方包和 feeds 依赖清单，避免新增隐藏的动态 clone 来源。
- 保留现有设备入口、配置文件和固件输出路径，降低迁移成本。

## 非目标

- 不把 OpenWrt/ImmortalWrt 完整源码直接 vendor 到主仓库普通目录中。
- 不一次性重写所有设备配置、feeds 逻辑或包定制逻辑。
- 不改变现有固件功能选择、默认主题、默认 LAN 地址和已有包集合。
- 不在主仓库中提交构建中间产物、下载缓存、toolchain、staging_dir 或 firmware 输出。

## 上游源码目录

按当前 `compilecfg/*.ini` 的 `BUILD_DIR` 聚合上游源码，目录如下：

```text
sources/
  immortalwrt/      # https://github.com/immortalwrt/immortalwrt.git master
  imm-nss/          # https://github.com/VIKINGYFY/immortalwrt.git main
  libwrt/           # https://github.com/LiBwrt/openwrt-6.x.git main-nss
  libwrt-k612/      # https://github.com/LiBwrt/openwrt-6.x.git k6.12-nss
  imm-mt798x/       # https://github.com/padavanonly/immortalwrt-mt798x.git openwrt-21.02
  airoha-wrt/       # https://github.com/ZqinKing/immortalwrt.git w1701k
```

设备配置继续使用现有 `wrt_core/compilecfg/<device>.ini`。构建脚本通过 `BUILD_DIR` 找到 `sources/<BUILD_DIR>`。

## 外部依赖边界

`sources/<BUILD_DIR>` 覆盖每个设备的主 OpenWrt/ImmortalWrt 源码树。`wrt_core/modules/packages.sh` 与 `wrt_core/modules/feeds.sh` 中显式 clone 的第三方包、feeds 或主题仓库必须登记到 `metadata/external-dependencies.tsv`，记录名称、URL、分支或 commit、目标路径和是否允许动态拉取。

如果某个第三方包需要本地直接修改，应把它提升为 `sources/packages/<name>` submodule，并让更新脚本优先使用本地 submodule 覆盖远程 clone。没有登记到依赖清单的新增 clone URL 应在 CI 校验中失败。

## 构建副本策略

OpenWrt 构建会修改源码树内的 `.config`、`feeds/`、`tmp/`、`build_dir/`、`staging_dir/`、`dl/`、`.ccache/` 等目录。为避免污染 submodule：

1. 本地和 CI 构建统一创建 `action_build/` 作为构建工作副本。
2. 构建副本从 `sources/<BUILD_DIR>` 同步得到，并排除 `.git` 与已知构建中间产物。
3. `wrt_core/update.sh` 在本地源码模式下跳过 `clone_repo` 与 `reset_feeds_conf`，只对构建副本执行 feeds 更新、包替换、主题设置、patch 应用和系统配置修改。
4. `build.sh` 在构建副本中执行 `make defconfig`、`make download` 和 `make`。
5. 构建产物继续复制到 `firmware/`。

这样可以同时满足：submodule 可直接修改，构建过程可重复，构建中间产物不会进入源码追踪。

## 修改追踪机制

上游源码修改分两层追踪：

- submodule 内提交：对上游源码的直接修改应提交到对应 submodule 仓库，主仓库只记录 submodule commit 指针。
- 补丁导出：提供脚本把 submodule 工作区差异导出到 `patches/local/<source-id>/`，便于代码审查、迁移和回滚。
- 依赖清单：`metadata/external-dependencies.tsv` 记录脚本仍需拉取的外部包来源，CI 校验实际脚本中的 clone URL 与清单一致。

建议把 submodule 远程地址指向用户自己的 fork 或组织镜像。否则 GitHub Actions 无法拉取只存在于本机的 submodule commit。

## 构建脚本改造

新增或调整以下能力：

- 解析设备 ini，得到 `REPO_URL`、`REPO_BRANCH`、`BUILD_DIR` 和 `COMMIT_HASH`。
- 校验 `sources/<BUILD_DIR>` 是否存在且为 Git 仓库或 submodule。
- 初始化构建副本 `action_build/`。
- 从源码目录同步到构建副本，排除 `.git`、`bin/`、`build_dir/`、`staging_dir/`、`tmp/`、`dl/`、`.ccache/` 等构建产物目录。
- 普通构建只生成 `action_build/.source-lock`，记录源码目录、远程地址、分支和 commit，避免污染主仓库。
- 显式执行 `scripts/update-source-locks.sh` 时才更新可提交的 `metadata/sources/*.lock`。
- 在 CI 中使用 submodule commit、设备配置和脚本 hash 参与缓存 key 与构建摘要。

## GitHub Actions 改造

`build_wrt.yml` 与 `release_wrt.yml` 需要同步更新：

- `actions/checkout` 先只检出主仓库，解析设备 ini 后仅初始化目标设备需要的 `sources/<BUILD_DIR>` submodule，避免每次构建拉取全部上游源码。
- 增加源码校验步骤，确认输入设备映射的 `sources/<BUILD_DIR>` 存在。
- 缓存 key 使用设备配置、源码 commit、`wrt_core` 脚本和补丁文件 hash。
- 构建后验证 `firmware/` 中至少存在 manifest 或固件文件。
- build workflow 上传 artifact。
- release workflow 保持 release 行为，并在 release body 中记录源码 commit。
- 现有 `Pre Clone` 步骤由 `scripts/prepare-source.sh` 与 `scripts/validate-source.sh` 替代；`wrt_core/pre_clone_action.sh` 保留为动态 clone 回滚入口，不再作为默认 CI 路径。

触发条件保留 `workflow_dispatch`，并可增加对 `main` 的 push 构建校验，但完整固件编译仍建议手动触发以控制资源消耗。

## 目录隔离规则

- `sources/`：只放上游源码 submodule。
- `wrt_core/`：只放本项目构建逻辑、设备配置、补丁与定制脚本。
- `metadata/`：放可提交的来源锁定信息和构建摘要模板。
- `patches/local/`：放可提交的本地差异导出补丁。
- `action_build/`：构建工作副本，必须忽略。
- `firmware/`：固件输出，继续忽略。

## 验证标准

最小验证：

```bash
git submodule status
./scripts/validate-source.sh x64_immwrt
./scripts/prepare-source.sh x64_immwrt
./build.sh x64_immwrt debug
```

CI 验证：

- workflow 能 checkout 主仓库和 submodule。
- source validation 能输出设备对应源码 commit。
- debug 构建能完成 `make defconfig`。
- 完整构建能生成 `firmware/` 产物并上传 artifact。
- CI 能发现脚本中未登记的外部 clone URL。

## 风险与回滚

风险：

- 上游源码体量较大，首次 clone 和 CI checkout 时间会上升。
- 如果 submodule 指向本机未推送 commit，CI 会失败。
- OpenWrt 构建副本同步如果遗漏隐藏文件或权限，可能导致构建行为差异。
- 第三方包依赖数量较多，全部提升为 submodule 会增加维护成本，因此先通过清单强制追踪，再按需要提升为本地 submodule。

回滚方式：

- 移除 `.gitmodules` 和 `sources/` submodule 指针。
- 恢复 `build.sh` 与 `wrt_core/pre_clone_action.sh` 的动态 clone 流程。
- 删除新增 `scripts/`、`metadata/`、`patches/local/` 中与 submodule 构建相关文件。

## 实施顺序

1. 添加 `sources/` submodule 映射和 `.gitmodules`。
2. 添加外部依赖清单，登记现有脚本中的第三方 clone 来源。
3. 添加源码准备、校验、锁定和补丁导出脚本。
4. 改造 `wrt_core/update.sh`，支持本地源码模式跳过主仓库 clone/reset/pull。
5. 改造 `build.sh`，让本地源码副本成为默认构建入口。
6. 改造 GitHub Actions checkout、缓存、校验和产物验证。
7. 更新 README，说明本地源码修改、submodule 更新和 CI 构建流程。
