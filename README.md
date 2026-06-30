# OpenWRT ImmWRT 定制固件编译框架

> 基于 ImmortalWRT / OpenWRT 的多设备定制固件自动化编译框架
> 作者:**superaddmin** · 仓库:[github.com/superaddmin/openwrt_immwrt](https://github.com/superaddmin/openwrt_immwrt)

本项目采用**源码仓库 + 定制脚本 + 配置/补丁**解耦的设计,构建时动态克隆上游 OpenWRT 源码,再通过模块化脚本对源码做原地补丁、包替换、feed 注入,最终编译出定制固件。支持本地编译、Docker 容器编译和 GitHub Actions CI 编译三种方式。

## 目录

- [快速开始](#快速开始)
- [支持的设备](#支持的设备)
- [编译模式](#编译模式)
- [项目结构](#项目结构)
- [配置系统](#配置系统)
- [定制特性](#定制特性)
- [OAF 应用过滤使用说明](#oaf-应用过滤使用说明)
- [常见问题](#常见问题)
- [技术文档](#技术文档)
- [致谢](#致谢)

---

## 快速开始

### 1. 环境准备

推荐 **Ubuntu LTS**(本地编译)。GitHub Actions CI 使用 `ubuntu-24.04`。

```bash
sudo apt -y update
sudo apt -y full-upgrade
sudo apt install -y dos2unix libfuse-dev
sudo bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)'
```

### 2. 克隆仓库

```bash
git clone https://github.com/superaddmin/openwrt_immwrt.git
cd openwrt_immwrt
```

### 3. 编译固件

```bash
# 命令行指定设备
./build.sh jdcloud_ipq60xx_immwrt

# 或交互式选择(不带参数)
./build.sh
```

编译产物输出到 `firmware/` 目录。

---

## 支持的设备

支持 17 款设备配置,覆盖高通 IPQ、联发科 Filogic、瑞芯微、x86 四大平台。详见 [设备适配文档](docs/设备适配.md)。

| 品牌 | 设备 | 编译命令 | 平台 |
|------|------|----------|------|
| 京东云 | 雅典娜(02)/亚瑟(01)/太乙(07)/AX5(JDC) | `./build.sh jdcloud_ipq60xx_immwrt` | IPQ60xx |
| 京东云 | 上述设备的 LibWrt 版 | `./build.sh jdcloud_ipq60xx_libwrt` | IPQ60xx |
| 京东云 | 百里(AX6000) | `./build.sh jdcloud_ax6000_immwrt` | IPQ807x |
| 阿里云 | AP8220 | `./build.sh aliyun_ap8220_immwrt` | IPQ60xx |
| 阿里云 | AP8220 (LibWrt) | `./build.sh aliyun_ap8220_libwrt` | IPQ60xx |
| 领势 | MX4200v1/v2/MX4300 | `./build.sh linksys_mx4x00_immwrt` | IPQ807x |
| 领势 | MR9600(NN6000v2) | `./build.sh link_nn6000v2_immwrt` | IPQ807x |
| 奇虎 | 360 V6 | `./build.sh qihoo_360v6_immwrt` | IPQ60xx |
| 红米 | AX5 | `./build.sh redmi_ax5_immwrt` | IPQ60xx |
| 红米 | AX6 | `./build.sh redmi_ax6_immwrt` | IPQ60xx |
| 红米 | AX6 (LibWrt) | `./build.sh redmi_ax6_libwrt` | IPQ60xx |
| 红米 | AX6000 | `./build.sh redmi_ax6000_immwrt21` | MT7986 |
| 中国移动 | RAX3000M | `./build.sh cmcc_rax3000m_immwrt` | MT7986 |
| 斐讯 | N1 盒子 | `./build.sh n1_immwrt` | ARMv8 |
| 兆能 | M2 | `./build.sh zn_m2_immwrt` | IPQ60xx |
| 兆能 | M2 (LibWrt) | `./build.sh zn_m2_libwrt` | IPQ60xx |
| Gemtek | W1701K | `./build.sh gemtek_w1701k_immwrt` | EN7527 |
| 通用 | x86_64 | `./build.sh x64_immwrt` | x86_64 |

---

## 编译模式

`build.sh` 支持四种编译模式,通过第二参数控制:

```bash
./build.sh <device> [normal|debug|container|container_debug]
```

| 模式 | 说明 |
|------|------|
| `normal`(默认) | 完整编译,生成固件到 `firmware/` |
| `debug` | 执行到 `make defconfig` 后停止,便于检查配置 |
| `container` | 在 Docker 容器(`immortalwrt/sdk`)中完整编译,环境隔离 |
| `container_debug` | 容器内编译到 defconfig 后进入交互式 shell |

**Docker 容器编译示例**:

```bash
./build.sh x64_immwrt container
```

容器模式会自动拉取 SDK 镜像、安装编译依赖、挂载仓库目录并执行编译,避免宿主环境不一致导致失败。

---

## 项目结构

```
openwrt_immwrt/
├── build.sh                  # 主入口:参数解析、配置应用、编译编排
├── .github/workflows/        # GitHub Actions CI 配置
│   ├── build_wrt.yml         # 编译工作流(支持 17 设备可选触发)
│   └── release_wrt.yml       # 发布工作流
├── wrt_core/                 # 核心模块目录
│   ├── update.sh             # 定制流程主编排(约 60 个步骤)
│   ├── pre_clone_action.sh   # CI 预克隆脚本
│   ├── build_container.sh    # Docker 容器构建入口
│   ├── compilecfg/           # 设备编译配置 (*.ini)
│   ├── deconfig/             # 设备内核/包配置 (*.config)
│   ├── modules/              # 模块化脚本
│   │   ├── general.sh        # 仓库克隆、清理、feeds 重置
│   │   ├── network.sh        # 网络重试封装(git/curl/wget)
│   │   ├── feeds.sh          # feeds 更新与安装
│   │   ├── packages.sh       # 包增删、第三方 feed 同步
│   │   ├── system.sh         # 系统级补丁与配置定制
│   │   ├── docker.sh         # Docker nftables 后端适配
│   │   └── cups.sh           # CUPS 打印服务依赖修复
│   └── patches/              # 补丁与资源文件
│       ├── *.patch           # 源码补丁
│       ├── 99*               # uci-defaults 启动脚本
│       ├── cpuusage/         # CPU 使用率采集脚本
│       └── openssl/          # OpenSSL 完整补丁集
├── docs/                     # 技术文档
└── firmware/                 # 编译产物输出(gitignore)
```

---

## 配置系统

每个设备由**一对文件**描述,文件名(去掉后缀)即设备标识符:

### INI 配置文件(`compilecfg/<device>.ini`)

描述上游源码仓库位置,字段如下:

| 字段 | 必填 | 说明 | 示例 |
|------|------|------|------|
| `REPO_URL` | 是 | 上游 OpenWRT 源码仓库 URL | `https://github.com/immortalwrt/immortalwrt.git` |
| `REPO_BRANCH` | 否 | 分支,默认 `main` | `master` |
| `BUILD_DIR` | 是 | 本地构建目录名 | `imm-nss` |
| `COMMIT_HASH` | 否 | 固定到指定 commit,默认 `none` | `a1b2c3d` |
| `BUILD_TARGET_SDK` | 否 | 容器编译用的 SDK 镜像,默认 `immortalwrt/sdk:openwrt-25.12` | — |

### CONFIG 配置文件(`deconfig/<device>.config`)

采用 OpenWRT Kconfig 语法(`CONFIG_XXX=y/n/m`),描述目标平台、设备型号、内核模块、软件包开关。

编译时 [build.sh](build.sh) 会按顺序追加以下配置:
1. 设备 config(`<device>.config`)
2. `nss.config`(仅 IPQ60xx/IPQ807x 设备,补充 NSS 加速支持)
3. `compile_base.config`(通用编译选项、主题、核心 LuCI 应用)
4. `docker_deps.config`(Docker 相关依赖)
5. `proxy.config`(代理工具链)

最后通过 `make defconfig` 自动展开依赖、解决冲突。

---

## 定制特性

框架在编译前对上游源码执行约 60 步定制,详见 [模块脚本文档](docs/模块脚本.md)。主要特性:

- **包管理**:移除上游重复的 passwall/ssr-plus/openclash 等,通过 sparse checkout 从 4 个第三方仓库精确拉取指定包
- **主题与界面**:默认 Argon 主题,定制 LAN 地址、CPU 采样、构建签名
- **网络加速**:NSS 硬件加速(IPQ 平台)、FullConeNAT、IRQ 亲和性优化
- **Docker nftables**:重写 dockerd/dockerman init 脚本,强制 nftables 后端
- **编译修复**:Linux 6.12/6.18 netfilter 兼容、Rust 编译、Kconfig 递归依赖等
- **第三方服务**:SmartDNS / mosDNS / AdGuardHome / Lucky / EasyTier / OAF 应用过滤等
- **网络健壮**:git/curl/wget 均带指数退避重试

---

## OAF 应用过滤使用说明

使用 OAF(应用过滤)功能前,需先完成以下操作:

1. 打开系统设置 → 启动项 → 定位到「appfilter」
2. 将「appfilter」当前状态**从已禁用更改为已启用**
3. 完成配置后,点击**启动**按钮激活服务

---

## 常见问题

**Q: 编译失败提示网络错误?**
A: 框架内置 `git_retry`/`curl_retry`/`wget_retry`(指数退避,最多 5 次)。若仍失败,检查网络或配置代理。

**Q: 如何切换上游源码版本?**
A: 修改对应设备的 `compilecfg/<device>.ini` 中的 `REPO_URL`、`REPO_BRANCH` 或设置 `COMMIT_HASH`。

**Q: 如何自定义预装软件包?**
A: 编辑 `deconfig/<device>.config`(设备专属)或 `deconfig/compile_base.config`(所有设备通用)。`y`=编入固件,`m`=可按需安装,`n`=不编译。

**Q: 容器编译与本地编译的区别?**
A: 容器编译使用官方 SDK 镜像,环境完全隔离,避免宿主依赖冲突。CI 默认使用本地编译 + ccache 缓存加速。

**Q: GitHub Actions 如何触发编译?**
A: 在仓库 Actions 页面选择 `Build WRT` 工作流,手动触发(workflow_dispatch)并选择设备型号。

---

## 技术文档

详细技术文档位于 [`docs/`](docs/) 目录:

- [技术架构](docs/技术架构.md) — 分层架构、设计理念、数据流
- [构建流程](docs/构建流程.md) — 编译全流程逐步解析
- [设备适配](docs/设备适配.md) — 17 款设备配置详情与平台映射
- [模块脚本](docs/模块脚本.md) — 60+ 定制函数参考手册

---

## 致谢

本项目基于以下开源项目构建:

- [ImmortalWRT](https://github.com/immortalwrt/immortalwrt) — 上游源码
- [LiBwrt OpenWrt](https://github.com/LiBwrt/openwrt-6.x) — LibWrt 分支
- [kenzok8/small-package](https://github.com/kenzok8/small-package) — 三方插件源
- [Openwrt-Passwall](https://github.com/Openwrt-Passwall/openwrt-passwall) — Passwall
- [sbwml/luci-app-mosdns](https://github.com/sbwml/luci-app-mosdns) — mosDNS
- 以及所有被引用的上游贡献者

## License

本项目遵循上游 ImmortalWRT / OpenWRT 的开源协议,详见 [LICENSE](LICENSE)。
