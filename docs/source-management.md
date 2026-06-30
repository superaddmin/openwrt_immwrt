# 上游源码管理

## 目录

- `sources/<source-id>`: 上游主源码 submodule。
- `action_build/`: 构建副本,由脚本自动生成,不提交。
- `metadata/external-dependencies.tsv`: 第三方动态依赖清单。
- `metadata/sources/*.lock`: 显式记录的源码锁定信息。
- `patches/local/<source-id>/`: 导出的本地源码差异补丁。

## 初始化单个设备源码

```bash
source_id=$(awk -F= '$1 == "BUILD_DIR" {print $2; exit}' wrt_core/compilecfg/x64_immwrt.ini)
git submodule update --init --depth 1 "sources/$source_id"
```

也可以直接初始化已知源码目录:

```bash
git submodule update --init --depth 1 sources/immortalwrt
```

## 修改和提交上游源码

在 submodule 内修改、提交并推送到 fork 或镜像,然后回到主仓库提交 submodule 指针。

```bash
cd sources/immortalwrt
git status
git commit -am "fix: 调整上游源码"
git push

cd ../..
git add sources/immortalwrt
git commit -m "chore: 更新immortalwrt源码指针"
```

如果 submodule 指向只存在于本机的 commit,GitHub Actions 无法检出该源码,构建会失败。

## 准备构建副本

默认构建会自动执行:

```bash
./scripts/prepare-source.sh x64_immwrt
```

该脚本把目标源码同步到 `action_build/`,并保留 `.ccache` 与 `staging_dir` 缓存目录。

## 导出补丁

```bash
./scripts/export-source-patches.sh immortalwrt
```

无工作区改动时不会生成空补丁。有改动时补丁会写入 `patches/local/<source-id>/`。

## 更新锁定信息

```bash
./scripts/update-source-locks.sh x64_immwrt
```

不传设备名时会遍历 `wrt_core/compilecfg/*.ini`,并按源码目录去重后写入 `metadata/sources/*.lock`。

## 校验源码和外部依赖

```bash
./scripts/validate-source.sh x64_immwrt
```

校验内容包括设备配置、`.gitmodules` 路径、submodule 初始化状态和 `metadata/external-dependencies.tsv` 中登记的固定远端依赖。

## 回滚动态 clone 模式

需要临时恢复旧流程时:

```bash
WRT_USE_DYNAMIC_CLONE=1 ./build.sh x64_immwrt debug
```

该模式会跳过 `sources/` 到 `action_build/` 的准备步骤,继续按 `compilecfg/<device>.ini` 动态 clone 上游仓库。
