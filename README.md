# xrcdemo

Arcaea iOS 练习插件，提供变速、进度跳转、循环练习、判定调整和 Konzetsu 效果练习，通过动态库注入运行。

| 项目 | 说明 |
| --- | --- |
| 适配版本 | 7.0.255 / 7.0.256；Konzetsu 练习适用于 7.0.256 |
| 运行组件 | `libxrcdemo.dylib` + `libellekit.dylib` |
| 构建环境 | GitHub Actions 或 macOS；Windows 可用于部署和签名 |
| 安装方式 | 准备配套 App → 注入 → 打包 → 签名 → 侧载 |

## 主要功能

- **练习控制**：播放倍率、保音高音乐变速、进度跳转、回跳重播、A/B 循环。
- **手感调整**：四档判定窗口、锁定判定区间、实时设置流速、按倍率自动适应偏移和流速。
- **Konzetsu 练习**：任意曲目应用下隐、变速、上下反、点血条或综合效果，可选挑战血条。
- **操作与内容**：游玩时隐藏悬浮图标、cb 内容外置、私服地址配置。

## 快速开始

1. 准备版本匹配、已解密且满足插件兼容条件的 App，解压到 `ios/Payload/Arc-mobile.app/`，保留原始备份。
2. 在 [Actions](https://github.com/TheBadRoger/Xrcdemo/actions) 构建，下载对应游戏版本的产物，将两个 dylib 放到项目根目录。
3. 在项目根目录运行：

   ```sh
   python inject.py --stub --brk --profile release
   python inject.py --check ios/Payload/Arc-mobile.app/Arc-mobile
   ```

4. 按 [安装方式](docs/installation.md) 打包、重新签名并安装。已有配套 IPA 时可直接从签名步骤开始。
5. 点击悬浮图标打开面板；长按图标切换倍率预设。Konzetsu 的选择在下一次加载谱面时应用。

## 文档

| 文档 | 内容 |
| --- | --- |
| [插件功能](docs/features.md) | 面板操作、默认设置、功能范围 |
| [实现原理](docs/architecture.md) | 注入结构、时钟与音频同步、版本适配 |
| [安装方式](docs/installation.md) | 构建、部署、签名、cb 导入及故障排查 |

游戏文件、IPA 和签名材料不随仓库发布。项目用途为离线练习及自有服务测试；与 lowiro 无关联。许可见 [LICENSE](LICENSE)，第三方组件说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

© 雾月星辰 & MLXC · github@XingChenRS · Xrcxex 附属项目
