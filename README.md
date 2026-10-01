# xrcdemo

Arcaea iOS 运行时改造套件（免越狱侧载）——**单层外挂 dylib + 精确定点的主程序补丁**。

> 定位：xrc 工作区 `projects/runtime-ios/` 下的 iOS 运行层；证据与研究记录在工作区 `research/notes/`。
> 基线：**Arcaea iOS 7.0.255**（跨版本适配见 §5）。版本与构建戳单一来源：`XRCVersion.h`。

## 1. 组成

| 部分 | 说明 |
|---|---|
| `libxrcdemo.dylib` | 全部运行时功能（本仓库根目录源码，Theos 构建） |
| `inject.py` | 主程序注入器：dylib 注入 / 判定桩 / BRK 站点 / Info.plist 补丁 / 状态清单——**使用前提** |
| 主程序补丁 | 精确到单指令与函数入口的定点改写（判定桩 12B、BRK 站点 4B）；不重打包、不动资源 |

## 2. 功能

| 功能 | 说明 |
|---|---|
| 回跳重播 | 回跳到已游玩并判定过的谱面段落时，支持重新游玩该段，同时清空分数记录 |
| seek 跳变 | 跳转到任意时刻并从该处播放；已判定音符不重现、计分不回滚 |
| 循环片段 | A/B 区间循环；与回跳重播配合形成练习闭环 |
| 变速 | 谱面流速（时钟域）＋ 音乐变速（保音高：FMOD 组速率 + 内置移调 DSP） |
| 改判 | 判定窗口四档动态调整；依赖主程序判定桩 |
| 自动演奏 | 全部判定强制 Pure（含漏扫路径），演示 / 练习用 |
| 私服接入 | API 域名重定向（路径参数原样、不动 TLS）＋ 请求 / 下载观测 |
| 内容外置 | cb 内容根免越狱外置到 Documents（容器内软链通道） |
| 解锁覆盖 | FV/DO 曲包五难度全解 + 终章链门放行（主程序补丁组） |
| cb 自由化 | 内容包校验恒通过且不再清树（离线自改内容的前提；主程序补丁组） |
| 防崩守链 | 7.0 链系统查表守崩桩（恒生效） |
| 日志与诊断 | 分级日志（4MB 滚动）；诊断工具（转储 / 探针 / 观测）随**开发构建**提供 |

## 3. 构建（双轴）

- **构建轴 `XRC_DEBUG`**：本地默认 `1`（开发构建：含调试工具与 DEBUG 日志）；
  发布构建显式 `make XRC_DEBUG=0`——`xrc_logd` 编译为空、内存转储 / 采集 / 观测段整段编出、
  NSLog 镜像关闭；面板调试区仅在开发构建中渲染。
- **功能轴（主程序补丁）**：由 `inject.py` 的 `--profile` / `--features` 选择注入哪些 BRK 站点；
  dylib 启动自检站点在位状态，面板据此显隐（不留死 UI）。
- 本地：Theos（`make`）；CI：GitHub Actions（`.github/workflows/build-tweak.yml`，发布构建走 `XRC_DEBUG=0`）。

## 4. 部署

1. `python inject.py --stub --brk`（对原始 `Arc-mobile`）：产出打桩主程序 + `xrc_patch_manifest.json`
   （含**状态清单**：判定桩态 / 站点在位 / 退役残桩 / dylib 哈希）。`--check` 可随时复核。
2. 将 `libxrcdemo.dylib` 与 `libellekit.dylib` 放入 `Payload/Arc-mobile.app/Frameworks/`，重签安装。
3. 校验：启动日志首行（版本 · 构建轴 · 基线）+ `[probe] summary` 一行给出全部 hook 状态。

## 5. 跨版本适配

- **只改 `XRCProfile.h`**：偏移宏 / 站点常量（每项带出处注释）；新版本按指纹重定位
  （判定核入口 3 指令、CMP 站点、各站点原字节 expect）。
- 站点表与 `inject.py` 常量手工同步（三处同步纪律：`XRCProfile.h` ↔ `inject.py` ↔ `XRCHook.m`）。
- 锚点优先走运行时 info blob；未命中回退编译期偏移（启动日志有告警）。

## 6. 设计纪律

- 面板设计源：`ui-mock/panel_mock.html`（改这里 = 改设计）。
- 证据纪律：二进制偏移必须在 `XRCProfile.h` 带出处注释。
- 交付面只描述最终行为（不含版本史 / 过程残留）。

© 雾月星辰 & MLXC · github@XingChenRS
