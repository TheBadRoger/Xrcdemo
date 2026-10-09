# 实时音乐倍速处理

状态：已实现，尚待 iOS 构建和实机音质、负载验证。日期：2026-10-09。

## 背景与选择

旧实现通过 FMOD 调整 BGM 播放速率，然后挂载内置 Pitch Shifter 补偿音高。
用户反馈非 1x 时音质较差。新实现改用 Signalsmith Stretch 1.3.2 的多声部频谱处理，
保留 FMOD 的源读取速率及位置时钟，使用自定义 DSP 替换原生移调器。

FMOD 的 read 回调要求输入、输出数量相同，因此此接入仍将源速率设为 `rate`，
在频谱处理器中设置 `1/rate` 的音高映射；组合结果是保音高倍速。
这不是独立解码原始 PCM 后按不同比例消耗输入的播放器，也不是预生成音频缓存。
避免另建播放器，是为了继续使用已有暂停、seek 和歌曲位置确认链路。

Signalsmith 默认质量预设处理多声部内容，启用 split computation 分散 FFT 计算，
iOS 使用 Accelerate 加速。Rubber Band R3 也能满足算法需求，但其 GPL/商业许可
与本项目现行许可的接入成本较高，故选择 MIT 许可的 Signalsmith。
极端倍率仍可能有音质损失，不能保证所有音乐都比旧算法更好，需实机试听对比。

## 同步和生命周期

- 自定义 DSP 初始化时从 FMOD 查询实际混音采样率。延迟为
  `(inputLatency + outputLatency) / sampleRate`，不再假定固定 48 kHz 或 FFT 窗口长度。
- 同一 BGM 组挂载后，回到 1x 仍保留固定延迟，避免频繁拆卸造成音频位置跳变。
  用户未使用过倍速时，不额外挂载 DSP。
- 换组时移除并释放旧 DSP，新组按需创建。初始化失败记录日志，退化为跟随速率但不保音高。
- 插件的前跳、回跳均发送缓冲重置请求。Retry 等原生位置回退也会清空缓冲，重新补偿。
  重置请求通过原子计数在混音线程执行，主线程不直接访问频谱处理器。
- 单声道、立体声处理器在创建时配置；read 回调不进行配置、堆分配、日志或加锁。
  暂停继续沿用原生 FMOD 通道暂停。

## 验证

`src/tests/audio_stretch.cpp` 通过实际处理器与模拟 FMOD 回调检查：
0.5–2x 音高、立体声反相关关系、seek 后无旧缓冲、速率变化后输出有限、
实际采样率对应的延迟，以及混音回调无堆分配。
macOS 测试使用 Accelerate 后端；Windows 使用便携 FFT 后端。

7.0.255 / 7.0.256 的 `System::createDSP` 和 `ChannelControl::removeDSP`
入口已在两个本地主程序副本中通过 IDA 核对序言与 API 调试串。
升级游戏时须重新核对这些入口、DSP 描述结构（arm64 为 0xD8 字节）及回调 ABI。

实机验收应包括 0.6x、0.75x、1.25x、1.5x 人声和密集打击乐试听，播放中调速，
前后拖动、暂停恢复、Retry、换歌，以及真机 CPU 占用和音频与判定偏差。

## 资料

- [Signalsmith 官方使用说明](https://github.com/Signalsmith-Audio/signalsmith-stretch)
- [FMOD 官方 DSP ABI 定义](https://github.com/fmod/fmod-for-unity/blob/master/Assets/Plugins/FMOD/src/fmod_dsp.cs)
- [Rubber Band 官方介绍与许可](https://www.breakfastquay.com/rubberband/)
