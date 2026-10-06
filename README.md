# xrcdemo

**Arcaea iOS 练习与定制客户端套件**。通过动态库和主程序补丁提供回跳重播、循环练习、变速、判定调整及私服接入能力，面向免越狱侧载场景。

| 项目 | 当前配置 |
| :--- | :--- |
| 适配基线 | **Arcaea iOS 7.0.255 / 7.0.256**；7.0.256 启动修复版已获用户真机可用反馈 |
| 构建目标 | iOS 14.0 起，`arm64` / `arm64e` |
| 运行组件 | `libxrcdemo.dylib` + `libellekit.dylib` |
| 注入工具 | Python 3.9+，仅使用标准库 |
| 安装流程 | 注入 → 校验 → 打包 IPA → 重新签名 → 侧载安装 |

> 构建目标不等于全部设备与系统版本均已验证。主程序补丁绑定游戏版本；其他版本必须先完成适配。
>
> 本项目与 lowiro 无关联，仅供学习交流及离线练习、私服测试使用。请勿将改造功能用于官方服务器；使用者自行承担使用后果。

**导航** · [功能](#功能) · [构建](#构建) · [部署](#部署) · [跨版本适配](#跨版本适配) · [故障排查](#故障排查) · [许可](#许可)

## 功能

| 功能 | 使用效果 |
| :--- | :--- |
| 回跳重播 | 回到已游玩的段落，重置相关判定与计分状态，让音符重新出现 |
| 时间跳转 | 跳到指定时刻；单独使用时不恢复已判定音符、不回滚计分 |
| A/B 循环 | 重复练习指定区间，可配合回跳重播使用 |
| 变速 | 调整谱面播放速度，并提供保音高的音乐变速 |
| 判定调整 | 四档判定窗口；需要注入判定桩 |
| 锁定判定区间（待真机验证） | 开启后，四档判定窗口按真实时间计算，避免播放倍率改变练习容错；默认关闭 |
| 下落流速输入（待真机验证） | 面板中直接输入音符下落速度，突破普通设置的 1.0–6.5 范围；与播放倍率独立 |
| 自动演奏 | 用于演示与练习；面板开关默认关闭 |
| 私服接入 | 重定向 API 地址，保留请求路径和参数 |
| 内容外置 | 将 cb 内容目录外置到 App 的 `Documents`，便于管理 |
| 锁态覆盖 | FV/DO 五难度锁态覆盖及终章链门放行；不会自动下载缺失内容 |
| cb 内容定制 | 放行内容包校验，保留现有内容树；内容就绪状态仍由游戏初始化流程决定 |
| 链系统保护 | 防止部分改名、移动曲包引起的空指针崩溃 |

配置：`Documents/xrcdemo.plist` · 日志：`Documents/xrcdemo.log`。

### 新增练习功能的部署状态

上述两个新增功能已加入源码，7.0.255 / 7.0.256 的新增补丁位置已定位。[配套动态库构建](https://github.com/TheBadRoger/Xrcdemo/actions/runs/37462696556)已生成产物；此前 Windows 因缺少 C 编译器跳过的判定边界与流速验证测试，已在 macOS 构建环境中通过。**当前可用反馈对应旧启动修复版，不代表这两个功能已经通过真机验证。** 新版需使用配套动态库，从未注入插件的主程序重新注入、打包、签名。旧动态库无法执行新增补丁，注入工具会拒绝混用。

| 配置项 | 默认值 | 使用说明 |
| :--- | :--- | :--- |
| `judgeTimeLock` | `false` | 面板开启“锁定判定区间”；四档窗口以真实毫秒为单位。独立的 Hold / Arc 连续判定逻辑仍需真机验证 |
| `noteFlow` | `0` | `0` 保留游戏设置；面板输入至少 `0.1` 的有限正数，按游戏原生精度取到一位小数，下一次开局生效 |

流速并非数学意义上的无限范围：受游戏 32 位设置字段约束。世界模式的固定流速规则保留；极端值的显示与可玩性尚未验证。播放倍率控制仍保持原有范围。

## 构建

### 1. 选择方式

| 方式 | 所需环境 | 产物 |
| :--- | :--- | :--- |
| **GitHub Actions（推荐）** | 可运行 Actions 的 GitHub 仓库 | 同一构建中的两个 dylib |
| **macOS 本地构建** | 完整 Xcode、Theos、iOS SDK、`ldid` | 需自行整理侧载动态库 |
| **Windows 部署** | Python、已构建的 dylib、签名工具 | 待签名 IPA；不是原生 iOS 编译流程 |

### 2. GitHub Actions 构建

1. 将源码推送到你的仓库。Fork 后如 Actions 尚未启用，先在 **Actions** 页面启用工作流。
2. 推送提交，触发 [Build xrcdemo](.github/workflows/build-tweak.yml)。也可在 Actions 中选择 **Build xrcdemo → Run workflow → ios 分支** 手动运行。
3. 等待构建成功，打开对应运行记录。
4. 下载 **Artifacts → `libxrcdemo-sideload-7.0.256`（或对应的 `7.0.255` 产物）**，将两个 dylib 解压到项目根目录。

 CI 会编译发布版、调整动态库依赖和安装名，并对 dylib 做临时签名。

**CI 产物不包含源 App 或可直接安装的 IPA。** 优先使用与当前源码提交一致的构建；部署时还需准备已解密的 App，并对整个 App 重新签名。

### 3. macOS 本地构建

安装完整 Xcode，按 [Theos 官方指南](https://theos.dev/docs/installation-macos) 配置 Theos 和 iOS SDK，并设置 `THEOS` 环境变量。当前 CI 使用 `iPhoneOS14.5.sdk`；完整流程见 [工作流文件](.github/workflows/build-tweak.yml)。

在项目根目录运行：

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

还需准备 `out/libellekit.dylib`：使用匹配的 CI 产物，或按工作流的 **Build ellekit** 步骤从 [ElleKit 源码](https://github.com/tealbathingsuit/ellekit) 构建。随后整理到根目录：

```sh
install_name_tool -id @rpath/libellekit.dylib out/libellekit.dylib
ldid -S out/libellekit.dylib
otool -L out/libxrcdemo.dylib
cp out/libxrcdemo.dylib out/libellekit.dylib .
```

检查 `otool -L` 输出，确保 hook 库依赖已改为 `@rpath/libellekit.dylib`。

| 设置 | 控制内容 | 使用场景 |
| :--- | :--- | :--- |
| `make XRC_DEBUG=0` | 关闭开发诊断工具和 DEBUG 日志 | 日常部署 |
| `make XRC_DEBUG=1` | 开发构建；本地 `make` 的默认值 | 调试源码 |
| `inject.py --profile release` | 发布版主程序补丁 | 日常部署 |
| `inject.py --profile dev` | 所有功能组，含高频调试站点 | 仅调试 |

这两类设置相互独立：`XRC_DEBUG` 控制动态库内容，`--profile` 控制主程序中打入哪些补丁。

## 部署

### 前置条件：使用配套砸壳 App

**必须使用与本套件配套的砸壳 App，并确保已完成解密和套件所需的相关校验检查处理。** 仅将官方 IPA 解压，或仅将主程序解密，不能证明满足全部运行条件。注入器不是完整的砸壳工具，也不会自动取消所有游戏校验。

砸壳包获取来源：[LingFeng751/ArcaeaDarkMode](https://github.com/LingFeng751/ArcaeaDarkMode)，下载文件及版本见其 [Releases](https://github.com/LingFeng751/ArcaeaDarkMode/releases)。按文件说明选择适用包：上游将 `Original.Plugin.ipa` 描述为未经修改的原版砸壳包，未承诺取消所有游戏内容校验，因此仍需核对具体包与套件的兼容性。

不要将关闭内容校验覆盖开关视为满足砸壳前置条件的替代方案。此前仅恢复启动的诊断配置已撤下；正常启动不等于全部功能验证通过。

| 游戏版本 | 当前状态 |
| :--- | :--- |
| 7.0.255 | 现有注入器和动态库的地址基线；需要配套砸壳 App |
| 7.0.256 | **已获真机可用反馈（2026-10-06）**：启动修复版 `4e580e5` 已完成构建、注入与静态检查；不代表全部功能均已逐项验收；详见 [适配记录](docs/ios-7.0.256-adaptation.md) |

**内容范围**：当前原始砸壳包及启动修复不提供免登录全曲包、全曲目、全 BYD/INS/ETR 难度、无限残片或全角色。锁态覆盖不会提供缺失资源或服务端授权。

**流程：准备文件 → 备份 → 注入 → 校验 → 打包 → 签名安装 → 真机验证**

以下命令均从项目根目录运行；若系统的 Python 命令为 `python3`，请相应替换 `python`。

### 1. 准备文件并备份

将你自行准备的、**满足上述砸壳前置条件且版本匹配**的 IPA 解压到 `ios/`，确保路径如下：

```text
xrcdemo/
├── inject.py
├── libxrcdemo.dylib
├── libellekit.dylib
└── ios/
    └── Payload/
        └── Arc-mobile.app/
            ├── Arc-mobile       ← 主程序
            ├── Info.plist
            └── Frameworks/
```

| 检查项 | 要求 |
| :--- | :--- |
| 游戏版本 | `7.0.255` 或 `7.0.256`；必须使用对应版本的动态库 |
| 主程序 | 使用配套砸壳版本；仅解压或解密不能代替相关校验检查处理 |
| 动态库 | 两个文件齐全，与注入器实现配套；也可放在 `ci-artifacts/libxrcdemo-sideload-7.0.256/`（按游戏版本选择） |
| 备份 | 保存完整源 App；注入器原位修改文件，不自动备份 |


### 2. 注入发布版补丁

注入器读取 App 的 `Info.plist` 自动选择游戏版本。7.0.256 必须使用重新构建的配套动态库，不能沿用 7.0.255 产物。

```sh
python inject.py --stub --brk --profile release
```

| 自动完成的操作 | 说明 |
| :--- | :--- |
| 复制动态库 | 将两个 dylib 放入 App 的 `Frameworks/` |
| 修改加载命令 | 加入动态库加载命令及所需搜索路径 |
| 写入判定桩 | 安装 v2 判定跳板与运行时锚点 |
| 写入功能补丁 | 发布组：`unlock_lock`、`chain_guard`、`cb_free`、`autoplay` |
| 修改 `Info.plist` | 配置网络访问及 Documents 文件共享 |
| 生成清单 | 根目录 `xrc_patch_manifest.json`，记录补丁状态和 dylib 哈希 |

**不要只复制 dylib 就安装，也不要只打桩而不加载 dylib。** 任一步报错，都应先处理错误再签名。

### 3. 校验补丁

```sh
python inject.py --check ios/Payload/Arc-mobile.app/Arc-mobile
```

应看到判定入口已修改、跳板为 **v2**、`@rpath/libxrcdemo.dylib present`，以及 `OK: stub v2 + dylib`。

| 清单检查 | 预期 |
| :--- | :--- |
| `state.judge_stub` / `state.load_dylib` | `v2` / `true` |
| 实际在位站点 | 与选定功能一致；未启用的调试站点可显示 `original` |
| `restore_sites.still_patched` | 空列表 |
| `brk_sites.unexpected` | 若非空，与原始主程序比较；未配置原字节指纹的站点也会出现在此处 |

> `--check` 是静态检查，不能代替签名验证和真机功能测试。

### 4. 按需修改名称与 Bundle ID

| 修改目标 | 操作 |
| :--- | :--- |
| 桌面名称，如 `Arc-Exercise` | 修改主 App 的 `CFBundleDisplayName`、`CFBundleName` |
| 独立安装标识 | 修改 `CFBundleIdentifier`，使用匹配的签名描述文件 |
| 保留 `.appex` 扩展 | 扩展 ID 必须以“主 App ID + `.`”开头，且扩展需单独签名 |
| 移除通知扩展 | 从待打包副本移除对应 `.appex`；会失去通知内容加工能力 |

例如：主 App 为 `moe.low.arc.exercise` 时，通知扩展应为 `moe.low.arc.exercise.NotificationServiceExtension`。仅修改显示名称无需修改可执行文件名或 `.app` 文件夹名。

### 5. 打包待签名 IPA

**IPA 是 ZIP 格式，顶层必须包含 `Payload/`。** 备份、日志、证书和补丁清单应留在包外。

macOS / Linux：

```sh
cd ios
zip -r ../Arc-Exercise-unsigned.ipa Payload
cd ..
```

Windows：将以下脚本保存为 `ios/package_ipa.py`，运行 `python ios/package_ipa.py`。脚本只打包 `Payload/`，并设置 App、扩展和 framework 可执行文件的权限。

```python
from pathlib import Path
import plistlib
import shutil
import zipfile

root = Path(__file__).resolve().parent
payload = root / "Payload"
executables = set()
for path in payload.rglob("Info.plist"):
    data = plistlib.loads(path.read_bytes())
    if data.get("CFBundleExecutable"):
        executables.add(path.parent / data["CFBundleExecutable"])
with zipfile.ZipFile(root / "Arc-Exercise-unsigned.ipa", "w",
                     compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(payload.rglob("*")):
        if not path.is_file():
            continue
        info = zipfile.ZipInfo.from_file(path, path.relative_to(root).as_posix())
        info.create_system = 3
        mode = 0o755 if path in executables or path.suffix == ".dylib" else 0o644
        info.external_attr = (0o100000 | mode) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        with path.open("rb") as source, archive.open(info, "w") as target:
            shutil.copyfileobj(source, target)
```

### 6. 签名与安装

| 签名方式 | 操作 |
| :--- | :--- |
| Apple ID 签名 | 将待签名 IPA 导入 Sideloadly 等工具，由工具签名并安装 |
| 自备证书 | 使用 `.p12` 和匹配的 `.mobileprovision`，通过 zsign 等工具签名 |
| 已签名 IPA | 使用安装工具直接安装；Sideloadly 选择 **Normal Install** |

自备证书的 [zsign](https://github.com/zhlynn/zsign) 命令示例：

```sh
zsign -k certificate.p12 -p 'YOUR_PASSWORD' \
  -m profile.mobileprovision \
  -o Arc-Exercise-signed.ipa Arc-Exercise-unsigned.ipa
```

 描述文件、证书、Bundle ID 和设备授权需要匹配。若描述文件限定了其他 Bundle ID，签名时用 `-b` 指定该 ID；保留扩展时还需匹配的扩展签名配置。

 dylib 的临时签名不等于 App 已具备安装资格；修改主程序、配置或动态库后，都必须重新签名。

### 7. 真机验证

- [ ] App 可正常安装、启动，悬浮球和练习面板可打开。
- [ ] 日志首行显示预期版本、构建标识和游戏基线。
- [ ] `[probe] summary` 中的判定与 hook 状态符合预期。
- [ ] 使用离线谱面检查回跳、循环、变速和判定调整。
- [ ] 确认 Documents 文件共享及内容外置符合设置。

## 跨版本适配

**不是修改一个版本号就能适配。** 新版本可能改变函数位置、对象布局和指令序列，必须重新定位、同步补丁，再构建验证。

| 步骤 | 需要完成的工作 | 涉及文件 |
| :--- | :--- | :--- |
| 1 准备样本 | 保留新版本已解密主程序及原始备份，确认架构和 Mach-O 段布局 | 新版本 App |
| 2 定位函数 | 按入口指令、调用关系和行为定位判定核、每帧更新、时钟及音频链 | 反汇编结果 |
| 3 核对布局 | 验证对象字段偏移、vtable 槽、函数参数与返回值 | `src/core/XRCProfile.h`、必要时 `xrc_abi.h` |
| 4 定位站点 | 更新站点地址及原字节指纹，不能直接沿用旧版本地址 | `inject.py`、`XRCProfile.h` |
| 5 分配跳板 | 确认 `__TEXT` / `__DATA` 中有足够零填充空间，跳板、slot、info blob 不重叠 | `inject.py` 的 `STUB_*`、BRK replay 地址 |
| 6 同步运行时 | 同步站点表、锚点、默认偏移及处理器，保持名称和布局一致 | `XRCProfile.h` ↔ `inject.py` ↔ `src/core/XRCHook.m` |
| 7 重建与注入 | 重新编译 dylib，对原始新版本 App 注入并执行 `--check` | 构建与部署流程 |
| 8 真机验收 | 分别验证启动、判定、回跳、循环、音频和内容功能，再确认支持范围 | 设备日志及实际游玩 |

适配时重点检查：

- **地址换算**：区分虚拟地址与文件偏移；新段布局不一定能继续用旧的减基址方式换算。
- **指令重放**：需要重放的原指令必须适合放入跳板，不能直接搬移 PC 相对指令。
- **锚点与回退**：info blob 只传递已定位地址，不会自动寻找新版本函数；编译期默认偏移也必须更新。
- **版本标识**：适配后更新基线说明；`src/core/XRCVersion.h` 中的套件版本不代表游戏兼容性。

原字节断言失败、跳板空间不足或计划外 BRK 报错时，应停止部署并重新检查定位结果。

## 故障排查

| 现象 | 优先检查 |
| :--- | :--- |
| `dylib missing` | 两个 dylib 是否在根目录或规定的 CI 产物目录 |
| `lack ... support` | 动态库与注入器标记不匹配；使用配套源码与构建产物 |
| 原字节断言失败 / `replay region not zero` | 游戏版本、原始备份及补丁地址；不要强行绕过断言 |
| `Mismatched bundle IDs` | `.appex` ID 是否以主 App ID 加 `.` 为前缀，签名工具是否再次改写了 ID |
| `contained no image slices` | 主程序 Mach-O 格式；旧注入器曾写入错误的 `0x8000000C`，正确的 `LC_LOAD_DYLIB` 为 `0x0000000C` |
| `Failed to re-fetch bundle during preflight` | 这是外层错误；读取设备 `installd` 日志中的底层错误再判断 |
| `DeviceNotSupportedByThinning` | 检查主 App 的 `UISupportedDevices`；若源包带有限定型号名单，先确认 `UIDeviceFamily` 支持目标设备，再移除名单并重新打包、签名。移除名单不会补回裁剪掉的资源 |
| 安装成功但启动崩溃 | 签名、动态库依赖、架构、功能处理器及游戏版本 |
| 面板出现但功能不可用 | 判定桩、选定功能站点及 `[probe] summary` 状态 |

注入器加载命令回归测试：

```sh
python -m unittest discover -s tests -v
```

## 许可

| 内容 | 说明 |
| :--- | :--- |
| 自有代码 | [LICENSE](LICENSE)：保留所有权利，附个人学习研究授权 |
| 上游与第三方组件 | [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) |
| 游戏文件与资源 | 由使用者自行准备，不随仓库分发 |

© 雾月星辰 & MLXC · github@XingChenRS · Xrcxex 附属项目
