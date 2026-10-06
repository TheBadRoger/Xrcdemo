# iOS 7.0.256 适配记录

当前状态：地址配置和注入器已更新，配套动态库构建、实际注入与静态检查已通过，等待真机验收。不得将静态检查通过视为完整兼容性证明。

## 样本

| 项目 | 值 |
| :--- | :--- |
| 游戏版本 / 构建 | 7.0.256 / 1209864 |
| 主程序 SHA-256 | `eae2722958eac2f7358d97a3a7e172726a59577fa15b98d70d747f7815d3e613` |
| 来源 | [ArcaeaDarkMode Releases](https://github.com/LingFeng751/ArcaeaDarkMode/releases)，`Arcaea.7.0.256.iOS.Original.Plugin.ipa` |

地址依据这个样本定位。同一版本号的其他修改包仍需核对原字节和布局。

## 改动与检查

| 范围 | 处理 |
| :--- | :--- |
| 判定入口 | 文件偏移由 `0x91E684` 更新为 `0x920788`，核对入口指令 |
| 跳板与运行时锚点 | 根据新 Mach-O 段布局重新分配，并核对零填充空间 |
| BRK 站点 | 重新定位 29 个站点，记录新版本原字节指纹 |
| 游戏、时钟及音频 | 核对函数指令、vtable、全局变量及运行时地址 |
| 回跳重播 | 将硬编码地址移入版本配置 |
| 构建 | 使用 `XRC_GAME_VERSION=7.0.256`，与 7.0.255 分开输出产物 |
| 注入 | 读取 App 的 `Info.plist` 选择配置；7.0.256 要求动态库包含匹配的版本标识 |

配置文件：[运行时地址](../src/core/XRCProfile_7_0_256.h)、[注入地址与指纹](../profiles/ios_7.0.256.json)。

## 验收步骤

1. 在 Actions 手动运行 **Build xrcdemo**，选择 `ios` 分支。
2. 下载本次运行的 `libxrcdemo-sideload-7.0.256`，替换项目根目录中的两个 dylib。
3. 从完整原始 App 副本开始，按 README 注入、检查、打包并重新签名。
4. 确认设备日志的编译配置为 `xrc-profile:7.0.256`。
5. 验证启动、判定、回跳、循环、音频及内容功能，保留日志和异常报告。

旧版 dylib 不能直接复用于这个版本。此前关闭 `cbBypass` 的诊断配置已撤下，不作为部署或兼容性结论。

## 本次部署检查

- 配套动态库包含 `xrc-profile:7.0.256`，不含旧版配置标识。
- 实际注入通过原字节断言；发布版启用 19 个站点，无计划外 BRK。
- `--check` 确认 v2 判定桩和动态库加载命令在位。
- 桌面名称为 `Arc-Exercise`，Bundle ID 为 `moe.low.arc.exercise`；部署包不含通知扩展，仍需完整重新签名。

## iPad 安装限制修正

源包的 `UISupportedDevices` 仅列出部分 iPhone 和 iPod，导致 iPad 安装时出现 `DeviceNotSupportedByThinning`。主 App 的 `UIDeviceFamily` 已为 `[1, 2]`，因此部署时移除型号白名单，保留原有 iPad 支持声明，并重新打包。新包必须重新签名。这个修改仅消除安装阶段的型号限制，不能证明原包包含全部 iPad 资源或已通过真机验证。

## iOS 26 启动看门狗修正

2026-10-06 的设备报告记录 `EXC_CRASH / SIGKILL`，终止码 `0x8BADF00D`，原因为创建场景超过约 19 秒。主线程停在 `s_install_other_stacks -> method_setImplementation -> flushCaches`；日志停在游戏网络回调安装之后，未输出 NSURLSession 探针安装完成。

发布版现在跳过全局 NSURLSession 工厂、Task resume 和额外 NSURLConnection 异步诊断探针，保留游戏使用的连接重定向及 DownloaderAppleImpl 回调。发布版日志会显示 `scoped-hooks v1`，用于确认实际安装了新构建。开发构建仍含这些诊断探针，不应作为本次修复的部署产物。

这个报告支持启动时网络探针安装阻塞的诊断，不支持将原因归为 cbBypass 或游戏地址不匹配。修复仍需设备复测。

## 首次内容初始化断言修正

17:33 的日志确认 `scoped-hooks v1` 已生效，网络钩子安装已完成。新的报告为 `SIGABRT / __assert_rtn`；原始主程序 `0x17DD9C` 前的调用参数明确为 `document.h:1226`、`Size`、`IsArray()`。调用方 `0x136748` 查询 cb 就绪状态后，在真值分支调用内容初始化；插件此前不论原生状态如何，都将这个 getter 强制返回真。设备日志同时显示首次启动没有 cb，仅创建了空占位目录。

修正：cb 就绪站点始终重放原 getter，等待游戏实际完成内容初始化；不再把目录存在或校验覆盖开关当作内容就绪。`cbBypass` 对文件/清单校验和清理保护的控制保持原样，不要求关闭整个开关。新构建日志包含 `cb-ready-native v1`。仍需真机验证初始化流程及内容下载；砸壳前置条件不能消除插件强制就绪造成的时序错误。
