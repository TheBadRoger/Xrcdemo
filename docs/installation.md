# 安装方式

[返回 README](../README.md) · [插件功能](features.md) · [实现原理](architecture.md)

## 1. 准备 App 和工具

| 所需内容 | 要求 |
| --- | --- |
| 源 App | 版本匹配的配套砸壳 App，已解密并满足套件所需校验兼容条件 |
| 游戏版本 | 7.0.255 或 7.0.256；其他版本先完成适配 |
| Python | Python 3.9+，注入器仅使用标准库 |
| 动态库 | 同一次构建的 `libxrcdemo.dylib` 与 `libellekit.dylib` |
| 签名工具 | Apple ID 侧载工具，或自备证书配合 zsign |
| 备份 | 完整原始 App；注入器会原位修改文件，不自动备份 |

仅解压官方 IPA 不等于已解密；仅解密也不能证明所有兼容条件已满足。注入器不负责完整砸壳。可参考 [ArcaeaDarkMode 仓库](https://github.com/LingFeng751/ArcaeaDarkMode)及其 [Releases](https://github.com/LingFeng751/ArcaeaDarkMode/releases)，核对具体文件与版本说明。

配置目标为 iOS 14.0 起、`arm64` / `arm64e`；不代表所有设备和系统均已验收。Windows 可执行部署和签名，本项目的 iOS 原生编译使用 macOS。

## 2. 构建动态库

### GitHub Actions

1. 将源码推送到自己的仓库，Fork 后在 Actions 页面启用工作流。
2. 推送提交触发 **Build xrcdemo**，或选择 **Run workflow**，确认目标分支。
3. 等待测试与构建成功。
4. 下载 `libxrcdemo-sideload-7.0.256` 或 `libxrcdemo-sideload-7.0.255`。
5. 把其中两个 dylib 解压到项目根目录。

[工作流](../.github/workflows/build-tweak.yml)分别构建两个版本，整理安装名和依赖并临时签名。产物只有动态库，不包含游戏或可直接安装的 IPA；整个 App 仍需重新签名。

### macOS 本地构建

安装完整 Xcode，按 [Theos 官方指南](https://theos.dev/docs/installation-macos)配置 Theos、iOS SDK 和 `THEOS`。当前工作流使用 `iPhoneOS14.5.sdk`。

```sh
brew install ldid
make clean
make XRC_DEBUG=0 XRC_GAME_VERSION=7.0.256
mkdir -p out
DYLIB=$(find .theos/obj -name 'xrcdemo.dylib' -not -path '*.dSYM*' | head -n 1)
test -n "$DYLIB" && cp "$DYLIB" out/libxrcdemo.dylib
install_name_tool -change \
  /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate \
  @rpath/libellekit.dylib out/libxrcdemo.dylib
install_name_tool -id @rpath/libxrcdemo.dylib out/libxrcdemo.dylib
ldid -S out/libxrcdemo.dylib
```

`libellekit.dylib` 使用匹配的 Actions 产物，或按工作流的 **Build ellekit** 步骤构建；其安装名应为 `@rpath/libellekit.dylib`。用 `otool -L out/libxrcdemo.dylib` 检查依赖，再将两个库复制到根目录。

## 3. 注入与检查

将 App 解压到以下路径，在项目根目录运行命令：

```text
xrcdemo/
  inject.py
  libxrcdemo.dylib
  libellekit.dylib
  ios/Payload/Arc-mobile.app/
    Arc-mobile
    Info.plist
    Frameworks/
```

```sh
python inject.py --stub --brk --profile release
python inject.py --check ios/Payload/Arc-mobile.app/Arc-mobile
```

版本从 `Info.plist` 读取，必须匹配动态库。默认发布功能包含判定锁定、倍率流速适配、链保护、cb 处理和自动演奏站点；7.0.256 还包含 Konzetsu。站点存在不代表面板开关已开启。

| 检查 | 预期 |
| --- | --- |
| 判定跳板 | `v2` |
| 加载命令 | `@rpath/libxrcdemo.dylib present` |
| 总体结果 | `OK: stub v2 + dylib` |
| 部署清单 | `state.judge_stub` 为 `v2`，`state.load_dylib` 为 `true` |
| 恢复站点 | `restore_sites.still_patched` 为空 |
| 功能与版本标记 | 与选定版本及新增站点配套，无原字节断言错误 |

注入失败时先修复，不直接签名。重新部署优先从未注入的备份副本开始；已经额外修改的主程序，应使用经过验证的配套部署流程，避免通用注入恢复原生改动。单独复制动态库不能补齐新增站点。

## 4. 设置名称、标识和设备支持

| 项目 | 设置 |
| --- | --- |
| 桌面名称 | `CFBundleDisplayName`、`CFBundleName` 设为 `Arc-Exercise` |
| Bundle ID | `CFBundleIdentifier` 与最终签名描述文件匹配 |
| 文件共享 | `UIFileSharingEnabled`、`LSSupportsOpeningDocumentsInPlace` 为 `true`；注入器会配置 |
| iPad 型号限制 | 确认 `UIDeviceFamily` 包含 `2` 后，检查是否需要移除源包的 `UISupportedDevices` 型号白名单 |
| 通知扩展 | 保留时扩展 ID 必须以主 App ID 加 `.` 开头，并使用配套签名；不需要时从待打包副本移除 `PlugIns` |

移除设备白名单不会补回源包已裁剪的资源。移除通知扩展会失去通知内容加工能力。显示名称、Bundle ID、主程序文件名分别是不同概念。

## 5. 打包 IPA

IPA 是 ZIP 文件，顶层必须包含 `Payload/`。使用独立待打包目录，保留原始样本。主程序、App 扩展和 framework 可执行文件应保留执行权限。

| 包内保留 | 包外保存 |
| --- | --- |
| 主程序、Info.plist、游戏资源、配套动态库 | 原始备份、补丁清单、日志、IDA 数据库、证书、密码 |
| 当前修改过的资源 | 旧 `_CodeSignature`、`SC_Info` 和 `embedded.mobileprovision` 不沿用 |
| 歌曲音频和谱面（如已准备） | 单独导入的 cb 热更新，不重复塞入 IPA |

待打包目录整理完成后，macOS 可使用：

```sh
cd ios
zip -r ../Arc-Exercise-unsigned.ipa Payload
cd ..
```

Windows 可从 `ios` 目录使用 Python 标准库打包，确保待打包文件已经排除上述杂物：

```powershell
Push-Location .\ios
python -m zipfile -c ..\Arc-Exercise-unsigned.ipa Payload
Pop-Location
```

Python 会使用磁盘权限；如来源解压工具没有保留可执行标记，应使用设置 ZIP Unix 执行权限的打包器，或在 macOS 整理后打包。打包后检查条目唯一性、CRC、主程序和动态库哈希，并核对用户修改的资源未被旧文件覆盖。

本地 `ios/deployment` 中的专用打包脚本仅用于当前样本，整个目录受 Git 忽略，不属于克隆仓库后即可使用的公共工具。已有配套 IPA 时无需重复注入。

## 6. 签名与安装

| 情况 | 做法 |
| --- | --- |
| 使用 Apple ID | 交给 Sideloadly 等工具签名并安装 |
| 自备证书 | 使用有效 `.p12` 和匹配 `.mobileprovision`，通过 zsign 签名 |
| 已经签好的 IPA | 使用直接安装；Sideloadly 选择 **Normal Install**，避免再次改写签名 |

证书、描述文件、Bundle ID 和设备授权需配套。修改主程序、动态库或 Info.plist 后，整个 App 都要重新签名。

本工作区已有交互签名脚本，密码由本人输入：

```powershell
.\ios\deployment\sign.ps1 -IpaPath ".\ios\deployment\你的未签名包.ipa"
```

该脚本和证书不随 Git 发布。其他环境按 [zsign](https://github.com/zhlynn/zsign)的参数要求准备签名工具；不要把证书密码写入仓库或共享命令记录。

## 7. cb 热更新导入

安装 IPA 不会直接填充应用数据容器。当前独立导入包对应布局：

```text
Documents/
  cb/
    meta.cb
    active/
      img/
      songs/
      tl/
```

1. 启用文件共享和 cb 外置，运行一次 App 建立目录。
2. 完全退出游戏，备份现有 `Documents/cb`。
3. 将配套导入包解压内容放入 Documents，避免出现 `cb/cb` 或 `active/active`。
4. `meta.cb` 和资源必须来自同一热更新版本；再启动游戏验证。

已取得的设备元数据对应应用 7.0.256、热更新 7.0.260；本地独立导入包已核对资源与元数据。仍需设备确认初始化，不应伪造就绪状态。歌曲完整音频和谱面与热更新是不同资源集合，不由插件自动提供。

## 8. 故障排查与验收

| 现象 | 检查方式 |
| --- | --- |
| `dylib missing` | 两个库是否位于根目录或对应 CI 产物目录 |
| `lack ... support` | 库版本、功能标记及注入器是否配套 |
| 原字节不符 / replay 空间占用 | 比较原始备份、版本、架构及已有修改，不绕过断言 |
| `Mismatched bundle IDs` | 主 App 和扩展 ID 前缀、描述文件及签名工具是否再次改写标识 |
| `Failed to re-fetch bundle during preflight` | 获取设备 `installd` 底层日志；外层提示不能单独确定原因 |
| `DeviceNotSupportedByThinning` | `UISupportedDevices` 与 `UIDeviceFamily` 是否允许该设备 |
| `contained no image slices` | Mach-O 结构和加载命令；`LC_LOAD_DYLIB` 应为 `0x0000000C` |
| 启动超时 / `0x8BADF00D` | 查看 `.ips` 主线程栈；曾遇网络诊断 hook 安装阻塞，使用匹配的发布构建排查 |
| `IsArray()` 断言 | 检查 cb 数据格式及初始化时序，不强制返回就绪 |
| 面板存在但功能无效 | 版本标记、`[probe] summary`、实际站点和当前开关；保存成功不等于运行成功 |
| 仍重复下载热更新 | 检查实际 Documents/cb 布局、元数据版本和资源完整性 |
| 点击曲目列表崩溃 | 保存 `.ips`、插件日志及相关资源清单；检查格式与引用完整性 |

运行闪退时，从设备“设置 → 隐私与安全性 → 分析与改进 → 分析数据”导出 App 的 `.ips`；同时通过文件共享获取 `Documents/xrcdemo.log`。安装失败优先获取 `installd` 日志，不能用运行日志代替。

| 真机检查 | 内容 |
| --- | --- |
| 启动与面板 | 正常进入、版本与构建标识正确 |
| 跳转与循环 | 前后跳转、快速拖动、取消、短循环、暂停及换歌 |
| 音画同步 | 低倍率 / 1x / 高倍率，音乐变速和两项适配分别检查 |
| 判定 | Tap / Hold / Arc / ArcTap，判定锁定开关分别检查 |
| Konzetsu | 五项循环选择、重新开局、橘色与挑战血条、综合时间表 |
| 图标 | 开关保存、游玩隐藏、退出恢复 |
| 内容 | 文件共享、cb 外置、热更新状态与歌曲资源 |

回归测试命令：`python -m unittest discover -s tests -v`。测试、安装、启动和完整功能验收是不同阶段。

## 提交与发布

游戏样本和产物保留在本地 `ios/Payload`、`ios/deployment`；`.gitignore` 忽略这些目录及 IPA、动态库、签名材料、设备日志。提交时只选择源码、版本配置、测试与文档，不把本地资源、分析文件或第三方工具带入仓库。

检查 `git diff --cached --stat` 和 `git diff --cached --check` 后再提交推送。需要新插件产物时，确认 Actions 测试与对应版本构建成功，再部署、签名和验收。
