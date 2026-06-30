# GitHub 自动发布独立 IPK 包设计

## 背景

当前仓库已经具备两条稳定链路：

- `build_wrt.yml`：构建固件并上传 artifact
- `release_wrt.yml`：构建固件并发布 GitHub Release

但仓库还缺少“只构建独立 `.ipk` 包并直接发布到 GitHub Release”的能力。对于只修改 LuCI 应用、单个服务包、第三方包或 feeds 包的场景，继续跑整机固件发布链路会带来三个问题：

1. 编译范围过大，耗时高。
2. 发布粒度过粗，不利于快速验证单包变更。
3. 用户想下载单个 `.ipk` 时，必须先从整机固件产物中额外拆解信息。

本设计新增一条面向“独立包发布”的工作流，在保持现有 submodule 构建机制不变的前提下，复用已有源码准备、定制脚本、配置合并和 defconfig 阶段，只把最终编译目标缩小到指定包。

## 目标

- 为仓库增加一条 GitHub Release 形式的独立 `.ipk` 自动发布链路。
- 复用现有 `sources/<source-id> -> action_build/` 的源码准备流程，不新增第二套源码管理方式。
- 支持按设备型号选择上游源码与 `.config`，确保包 ABI 与目标固件配置一致。
- 支持通过手动输入的包目标列表构建指定包，而不是强制整机固件编译。
- 自动收集 `.ipk` 产物、构建校验信息、源码锁信息和校验和文件，并作为 Release 附件发布。

## 非目标

- 不在本次实现中发布 `opkg feed`、`Packages.gz` 或 GitHub Pages 软件源。
- 不替换现有 `release_wrt.yml` 固件发布链路。
- 不新增“每次 push 自动构建并发布 `.ipk`”的默认触发策略，避免误发版本。
- 不尝试推断所有包的最优发布粒度；具体构建哪些包仍由 workflow 输入控制。

## 设计选择

### 选择 Release 附件而不是 gh-pages feed

本次采用 GitHub Release 附件发布 `.ipk`，原因：

- 与现有 `release_wrt.yml` 的发布方式一致，认知成本低。
- 不需要额外维护 `Packages` 索引和软件源目录布局。
- 对于“修改一个包并快速发版”的目标更直接。
- 保留后续扩展到 `gh-pages` feed 的空间。

### 选择专用脚本而不是继续扩展 `build.sh`

本次不把 `build.sh` 扩展成“大一统入口”，而是新增 `scripts/build-ipk.sh`：

- `build.sh` 继续专注整机固件编排。
- `scripts/build-ipk.sh` 复用 `./build.sh <device> debug` 产出的 `action_build/` 环境。
- 独立包构建逻辑、产物收集逻辑和 Release 元数据逻辑集中在一个脚本中，边界更清晰。

## 包构建链路

### 输入

`scripts/build-ipk.sh` 读取以下输入：

- `device`：设备名，对应 `wrt_core/compilecfg/<device>.ini`
- `WRT_IPK_TARGETS` 或命令行参数：OpenWrt 包构建目标列表
- `WRT_IPK_ARTIFACT_PATTERNS`：可选的产物收集模式

### 目标语义

包构建目标采用 OpenWrt make 目标语义，支持以下形式：

- `package/luci-app-timecontrol`
- `package/feeds/custom_feed/luci-app-mosdns`
- `feeds/custom_feed/lucky`
- `luci-app-timecontrol`（默认补全为 `package/luci-app-timecontrol`）

脚本会把目标统一规整为 `package/...`，再执行：

```bash
make <target>/download
make <target>/compile
```

### 复用现有调试构建

脚本先执行：

```bash
./build.sh <device> debug
```

这样可以直接复用：

- submodule 初始化后的 `prepare-source.sh`
- `update.sh` 定制流程
- 设备 config + 通用 config 合并
- `make defconfig`

随后在 `action_build/` 内继续执行包级别编译，不触发整机固件构建。

### 产物收集

脚本新增 `ipk_artifacts/<device>/` 作为独立包发布产物目录，并写入：

- `.ipk` 文件
- `sha256sums.txt`
- `package-targets.txt`
- `artifact-patterns.txt`（如有）
- `source-lock.txt`

收集规则：

- 若未提供 `WRT_IPK_ARTIFACT_PATTERNS`，默认收集“本次包编译后新生成或新更新”的 `.ipk`
- 若提供模式，则按模式精确筛选，避免把依赖包或历史缓存包全部带入 Release

## GitHub Actions 工作流

新增 `release_ipk.yml`，触发方式为 `workflow_dispatch`，输入包括：

- `model`
- `package_targets`
- `artifact_patterns`

主流程：

1. 构建机环境初始化
2. checkout 主仓库
3. 解析 `BUILD_DIR`
4. 仅初始化目标设备需要的 submodule
5. 运行 `scripts/validate-source.sh`
6. 导出 `SOURCE_COMMIT`
7. 恢复 `action_build/.ccache` 和 `action_build/staging_dir` 缓存
8. 调用 `scripts/build-ipk.sh`
9. 校验 `ipk_artifacts/<device>/` 至少存在一个 `.ipk`
10. 生成 release body
11. 通过 `softprops/action-gh-release` 发布 Release 附件

## 结果追踪机制

为便于审查和回溯，独立包发布产物目录保存以下上下文：

- `source-lock.txt`：对应 `action_build/.source-lock`
- `package-targets.txt`：本次构建目标清单
- `artifact-patterns.txt`：本次收集规则
- `sha256sums.txt`：Release 附件校验和

Release 正文同时记录：

- 设备型号
- 上游源码 URL
- 上游源码 commit
- 包构建目标
- `.ipk` 文件列表

## 目录隔离

- `action_build/`：继续作为构建副本目录，不提交
- `firmware/`：继续仅用于固件输出，不参与 `.ipk` 发布
- `ipk_artifacts/`：新增独立包发布输出目录，必须忽略
- `sources/`：继续只存放上游源码 submodule

## 验证标准

最小静态验证：

```bash
bash -n scripts/build-ipk.sh scripts/*.sh build.sh wrt_core/update.sh wrt_core/modules/general.sh wrt_core/build_container.sh
actionlint .github/workflows/release_ipk.yml
```

逻辑验证：

- workflow 能正确解析设备对应的 `SOURCE_ID`
- workflow 只初始化目标 submodule
- `scripts/build-ipk.sh` 能解析包目标列表
- 产物目录至少含一个 `.ipk`
- Release body 中包含 source commit 和包目标

## 风险与缓解

风险：

- 包目标写错时，OpenWrt `make package/.../compile` 会直接失败。
- 不同 source tree 中同名包的目录位置可能不同。
- 未指定 `artifact_patterns` 时，首次编译可能把相关依赖 `.ipk` 一并收集出来。

缓解：

- 在 workflow 输入说明中明确要求填写 OpenWrt 包构建目标。
- 保留 `artifact_patterns` 精确筛选能力。
- 在 `scripts/build-ipk.sh` 中输出标准化后的包目标清单，便于排查。
