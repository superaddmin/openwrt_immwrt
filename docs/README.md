# 技术文档

本目录包含 OpenWRT ImmWRT 定制固件编译框架的详细技术文档。

## 文档索引

| 文档 | 内容 | 适用读者 |
|------|------|----------|
| [技术架构.md](技术架构.md) | 分层架构、设计理念、构建副本机制、数据流、扩展点 | 想理解整体设计的开发者 |
| [构建流程.md](构建流程.md) | 从 `./build.sh` 到产出的完整流程逐步解析、CI 特有流程 | 排查编译问题、定制流程的开发者 |
| [设备适配.md](设备适配.md) | 17 款设备配置详情、6 个 source submodule 映射、新增设备指南 | 添加新设备、了解设备差异的用户 |
| [模块脚本.md](模块脚本.md) | 60+ 定制函数参考手册,按模块分组 | 修改/扩展现有定制的开发者 |
| [source-management.md](source-management.md) | submodule 初始化、源码修改、补丁导出、锁定、校验、回滚 | 需要修改或管理上游源码的开发者 |

## 阅读建议

- **初次接触**:先读 [技术架构.md](技术架构.md) 理解设计(含 submodule + 构建副本机制),再看 [构建流程.md](构建流程.md) 了解执行顺序
- **想编译固件**:看主 [README](../README.md) 的快速开始即可
- **想加新设备**:读 [设备适配.md](设备适配.md) 的"新增设备指南"
- **想改定制逻辑**:读 [模块脚本.md](模块脚本.md) 找到对应函数,在 [update.sh](../wrt_core/update.sh) 的 `main()` 中调整
- **想改上游源码**:读 [source-management.md](source-management.md) 了解 submodule 修改与指针更新流程
- **排查编译失败**:读 [构建流程.md](构建流程.md) 的"故障排查"章节

## 架构演进说明

本项目从"动态 clone 上游"演进为"submodule + 构建副本"架构。新架构下:
- 上游源码作为 git submodule 纳入 `sources/<source-id>/`,commit 由指针锁定
- 构建时通过 `scripts/prepare-source.sh` 同步到 `action_build/` 副本
- 外部依赖 URL 集中登记在 `metadata/external-dependencies.tsv`,`validate-source.sh` 强制校验
- 旧动态 clone 模式可通过 `WRT_USE_DYNAMIC_CLONE=1` 回退

详见 [技术架构.md](技术架构.md) 的"设计理念"章节。

## 文档维护

文档与代码同步更新。若修改了以下内容,请相应更新文档:

| 修改内容 | 需更新的文档 |
|----------|-------------|
| 新增/删除设备 | 设备适配.md |
| 新增/修改 update.sh 步骤 | 模块脚本.md + 构建流程.md |
| 修改 build.sh 流程 | 构建流程.md |
| 修改项目结构 / 源码管理机制 | 技术架构.md + source-management.md + 主 README |
| 新增外部依赖 URL | metadata/external-dependencies.tsv(validate-source 强制) |
| 新增/修改 scripts/ 脚本 | source-management.md + 技术架构.md |
