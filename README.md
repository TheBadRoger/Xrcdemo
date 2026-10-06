# xrcdemo

**Arcaea iOS 练习与定制客户端套件**。通过动态库和主程序补丁提供回跳重播、循环练习、变速、判定调整及私服接入能力，面向免越狱侧载场景。

| 项目 | 当前配置 |
| :--- | :--- |
| 🎮 适配基线 | **Arcaea iOS 7.0.255** |
| 📱 构建目标 | iOS 14.0 起，`arm64` / `arm64e` |
| 🧩 运行组件 | `libxrcdemo.dylib` + `libellekit.dylib` |
| 🛠️ 注入工具 | Python 3.9+，仅使用标准库 |
| 📦 安装流程 | 注入 → 校验 → 打包 IPA → 重新签名 → 侧载安装 |

> 构建目标不等于全部设备与系统版本均已验证。主程序补丁绑定游戏版本；其他版本必须先完成适配。
>
> 本项目与 lowiro 无关联，仅供学习交流及离线练习、私服测试使用。请勿将改造功能用于官方服务器；使用者自行承担使用后果。

**导航** · [功能](#功能) · [构建](#构建) · [部署](#部署) · [跨版本适配](#跨版本适配) · [故障排查](#故障排查) · [许可](#许可)

## 功能

| 功能 | 使用效果 |
| :--- | :--- |
| ↩️ 回跳重播 | 回到已游玩的段落，重置相关判定与计分状态，让音符重新出现 |
| ⏩ 时间跳转 | 跳到指定时刻；单独使用时不恢复已判定音符、不回滚计分 |
| 🔁 A/B 循环 | 重复练习指定区间，可配合回跳重播使用 |
| 🎵 变速 | 调整谱面播放速度，并提供保音高的音乐变速 |
| 🎯 判定调整 | 四档判定窗口；需要注入判定桩 |
| ▶️ 自动演奏 | 用于演示与练习；面板开关默认关闭 |
| 🌐 私服接入 | 重定向 API 地址，保留请求路径和参数 |
| 📂 内容外置 | 将 cb 内容目录外置到 App 的 `Documents`，便于管理 |
| 🔓 锁态覆盖 | FV/DO 五难度锁态覆盖及终章链门放行；不会自动下载缺失内容 |
| 🧩 cb 内容定制 | 放行内容包校验，保留现有内容树 |
| 🛡️ 链系统保护 | 防止部分改名、移动曲包引起的空指针崩溃 |

配置：`Documents/xrcdemo.plist` · 日志：`Documents/xrcdemo.log`。

## 构建

### ① 选择方式

| 方式 | 所需环境 | 产物 |
| :--- | :--- | :--- |
| **GitHub Actions（推荐）** | 可运行 Actions 的 GitHub 仓库 | 同一构建中的两个 dylib |
| **macOS 本地构建** | 完整 Xcode、Theos、iOS SDK、`ldid` | 需自行整理侧载动态库 |
| **Windows 部署** | Python、已构建的 dylib、签名工具 | 待签名 IPA；不是原生 iOS 编译流程 |

### ② GitHub Actions 构建

1. 将源码推送到你的仓库。Fork 后如 Actions 尚未启用，先在 **Actions** 页面启用工作流。
2. 推送提交，触发 [Build xrcdemo](.github/workflows/build-tweak.yml)。当前工作流仅配置了 `push` 触发。
3. 等待构建成功，打开对应运行记录。
4. 下载 **Artifacts → `libxrcdemo-sideload`**，将两个 dylib 解压到项目根目录。

✅ CI 会编译发布版、调整动态库依赖和安装名，并对 dylib 做临时签名。

⚠️ **CI 产物不包含源 App 或可直接安装的 IPA。** 优先使用与当前源码提交一致的构建；部署时还需准备已解密的 App，并对整个 App 重新签名。

### ③ macOS 本地构建

安装完整 Xcode，按 [Theos 官方指南](https://theos.dev/docs/installation-macos) 配置 Theos 和 iOS SDK，并设置 `THEOS` 环境变量。当前 CI 使用 `iPhoneOS14.5.sdk`；完整流程见 [工作流文件](.github/workflows/build-tweak.yml)。

在项目根目录运行：

```sh
brew install ldid
make clean
make XRC_DEBUG=0
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

**流程：准备文件 → 备份 → 注入 → 校验 → 打包 → 签名安装 → 真机验证**

以下命令均从项目根目录运行；若系统的 Python 命令为 `python3`，请相应替换 `python`。

### ① 准备文件并备份

将你自行准备的、**已解密且版本匹配**的 IPA 解压到 `ios/`，确保路径如下：

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
| 游戏版本 | `7.0.255`；其他版本见跨版本适配 |
| 主程序 | 已解密；“IPA 已解压”不等于“主程序已解密” |
| 动态库 | 两个文件齐全，与注入器实现配套；也可放在 `ci-artifacts/libxrcdemo-sideload/` |
| 备份 | 保存完整源 App；注入器原位修改文件，不自动备份 |

⚠️ **全新安装首次启动**：当前版本默认开启 `cbBypass`。在尚未初始化 cb 内容的设备上，已观察到启动闪退；关闭此项后可正常启动。建议首次启动使用 [首次启动配置](examples/first-launch/xrcdemo.plist)，具体操作见下方[已验证的启动问题](#已验证的启动问题)。

### ② 注入发布版补丁

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

### ③ 校验补丁

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

### ④ 按需修改名称与 Bundle ID

| 修改目标 | 操作 |
| :--- | :--- |
| 桌面名称，如 `Arc-Exercise` | 修改主 App 的 `CFBundleDisplayName`、`CFBundleName` |
| 独立安装标识 | 修改 `CFBundleIdentifier`，使用匹配的签名描述文件 |
| 保留 `.appex` 扩展 | 扩展 ID 必须以“主 App ID + `.`”开头，且扩展需单独签名 |
| 移除通知扩展 | 从待打包副本移除对应 `.appex`；会失去通知内容加工能力 |

例如：主 App 为 `moe.low.arc.exercise` 时，通知扩展应为 `moe.low.arc.exercise.NotificationServiceExtension`。仅修改显示名称无需修改可执行文件名或 `.app` 文件夹名。

### ⑤ 打包待签名 IPA

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

### ⑥ 签名与安装

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

✅ 描述文件、证书、Bundle ID 和设备授权需要匹配。若描述文件限定了其他 Bundle ID，签名时用 `-b` 指定该 ID；保留扩展时还需匹配的扩展签名配置。

⚠️ dylib 的临时签名不等于 App 已具备安装资格；修改主程序、配置或动态库后，都必须重新签名。

### ⑦ 真机验证

- [ ] App 可正常安装、启动，悬浮球和练习面板可打开。
- [ ] 日志首行显示预期版本、构建标识和游戏基线。
- [ ] `[probe] summary` 中的判定与 hook 状态符合预期。
- [ ] 使用离线谱面检查回跳、循环、变速和判定调整。
- [ ] 确认 Documents 文件共享及内容外置符合设置。

## 跨版本适配

**不是修改一个版本号就能适配。** 新版本可能改变函数位置、对象布局和指令序列，必须重新定位、同步补丁，再构建验证。

| 步骤 | 需要完成的工作 | 涉及文件 |
| :--- | :--- | :--- |
| 1️⃣ 准备样本 | 保留新版本已解密主程序及原始备份，确认架构和 Mach-O 段布局 | 新版本 App |
| 2️⃣ 定位函数 | 按入口指令、调用关系和行为定位判定核、每帧更新、时钟及音频链 | 反汇编结果 |
| 3️⃣ 核对布局 | 验证对象字段偏移、vtable 槽、函数参数与返回值 | `src/core/XRCProfile.h`、必要时 `xrc_abi.h` |
| 4️⃣ 定位站点 | 更新站点地址及原字节指纹，不能直接沿用旧版本地址 | `inject.py`、`XRCProfile.h` |
| 5️⃣ 分配跳板 | 确认 `__TEXT` / `__DATA` 中有足够零填充空间，跳板、slot、info blob 不重叠 | `inject.py` 的 `STUB_*`、BRK replay 地址 |
| 6️⃣ 同步运行时 | 同步站点表、锚点、默认偏移及处理器，保持名称和布局一致 | `XRCProfile.h` ↔ `inject.py` ↔ `src/core/XRCHook.m` |
| 7️⃣ 重建与注入 | 重新编译 dylib，对原始新版本 App 注入并执行 `--check` | 构建与部署流程 |
| 8️⃣ 真机验收 | 分别验证启动、判定、回跳、循环、音频和内容功能，再确认支持范围 | 设备日志及实际游玩 |

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
| 安装成功但启动崩溃 | 签名、动态库依赖、架构、功能处理器及游戏版本 |
| 面板出现但功能不可用 | 判定桩、选定功能站点及 `[probe] summary` 状态 |

### 已验证的启动问题

**首次安装没有 cb 内容，开启 `cbBypass` 时可能启动闪退。** 该配置不仅放行内容校验，还会让 `cb_ready` 无条件返回“已就绪”；就绪状态不能证明内容已经初始化。

| 项目 | 实测记录 |
| :--- | :--- |
| 验证日期 | 2026-10-06 |
| 环境 | iPad（`iPad12,1`）、iPadOS 26.6.1、Arcaea 7.0.255 |
| 套件 | 发布构建 `e4af9aa-10011916`，主程序已修正 Mach-O 加载命令，未包含通知扩展 |
| 启动日志 | SIGTRAP 处理器已安装；首次启动无既有 cb，仅创建 `Documents/cb` 占位目录 |
| 崩溃报告 | `document.h:1226`、`Size`、`IsArray()` 断言失败，经 `__assert_rtn → abort` 退出；报告中的断点地址对应 `cb_ready` |
| 最小验证 | 无需重新签名或安装，将 `cbBypass` 设为 `false` 后重新启动 |
| 用户确认结果 | **可正常启动**；其他练习功能及不同设备、版本仍需分别验证 |

**处理步骤：**

1. 完全退出 App，备份 `Documents/xrcdemo.plist`。
2. 若已有配置，仅将 `cbBypass` 改为 `false`，保留其他键：

   ```xml
   <key>cbBypass</key>
   <false/>
   ```

3. 若没有自定义配置，可使用 [examples/first-launch/xrcdemo.plist](examples/first-launch/xrcdemo.plist)。此文件仅指定 `cbBypass=false`，其他设置采用套件默认值。
4. 将文件以 **`xrcdemo.plist`** 的名称放回 App 的 Documents 根目录。在 iPad 上对应“文件 → 我的 iPad → App 显示名称”，不要放入 `cb` 子目录。
5. 重新启动并检查 `xrcdemo.log`。如果仍闪退，获取新的 `.ips`，确认是否仍为同一断言。

此操作关闭 cb 校验覆盖，但保留已注入的其他功能。它不会移除既有的内容外置软链，也不要求清空 cb 或卸载 App。启动验证通过后先保持 `cbBypass` 关闭；重新开启前需要确认内容已完整初始化。

> 这是已验证的配置规避方式，源码的默认值和强制就绪逻辑尚未修改；未据此宣称所有首次启动问题都已修复。

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
