# 独立 IPK 发布

> 本文档说明如何在本仓库中构建并发布独立 `.ipk` 包。

## 适用场景

当你只修改了单个 LuCI 应用、服务包、第三方包或 feed 包，而不想重新发布整机固件时，可以使用独立 `.ipk` 发布链路。

## 本地构建入口

```bash
./scripts/build-ipk.sh <device> [package-target ...]
```

示例：

```bash
./scripts/build-ipk.sh x64_immwrt luci-app-timecontrol
./scripts/build-ipk.sh jdcloud_ipq60xx_immwrt feeds/custom_feed/lucky
WRT_IPK_TARGETS="package/luci-app-timecontrol,feeds/custom_feed/luci-app-mosdns" ./scripts/build-ipk.sh x64_immwrt
```

## 包目标写法

支持三种写法，内部会统一规整为 OpenWrt `package/...` 目标：

- `luci-app-timecontrol`
- `package/luci-app-timecontrol`
- `feeds/custom_feed/lucky`

## 构建流程

`scripts/build-ipk.sh` 会先复用：

```bash
./build.sh <device> debug
```

完成 `action_build/`、feeds 和 `.config` 准备，然后预热 OpenWrt host 工具、工具链和目标内核产物：

```bash
make tools/install
make toolchain/install
make target/compile
```

最后只对指定包执行：

```bash
make <target>/download
make <target>/compile
```

## 产物目录

输出到：

```text
ipk_artifacts/<device>/
```

目录中包含：

- `*.ipk`
- `sha256sums.txt`
- `package-targets.txt`
- `artifact-patterns.txt`（若设置）
- `source-lock.txt`
- `device.txt`

## 产物筛选

默认收集“本次编译后新增或新更新”的 `.ipk`。

如果只想上传主包或主包加语言包，可以设置：

```bash
WRT_IPK_ARTIFACT_PATTERNS="*/luci-app-timecontrol_*.ipk,luci-app-timecontrol-zh-cn_*.ipk" ./scripts/build-ipk.sh x64_immwrt luci-app-timecontrol
```

## GitHub Actions 工作流

新增工作流：

```text
.github/workflows/release_ipk.yml
```

触发方式：`workflow_dispatch`

输入项：

- `model`
- `package_targets`
- `artifact_patterns`

工作流会把生成的 `.ipk` 作为 GitHub Release 附件发布。

## 注意事项

1. `package_targets` 必须对应当前 source tree 中真实存在的 OpenWrt 包目标。
2. 若只想上传主包，建议同时填写 `artifact_patterns`。
3. GitHub Actions 只能访问已经推送到远端的 submodule commit。
