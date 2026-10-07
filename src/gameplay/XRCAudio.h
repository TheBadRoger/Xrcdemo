// © 雾月星辰 & MLXC · github@XingChenRS
// XRCAudio.h — 音乐变速：让 BGM 跟着游戏速度走，且**保持音高**。
//
// 问题：现有变速只 warp 了游戏时钟（谱面按 rate 走），BGM 仍按 1.0x 放 ⇒ 速度 ≠ 1 时必然错开。
// 做法（磁带变速 + 移调补回；直接用 FMOD 自带的移调 DSP，不引第三方库）：
//   ① FMOD ChannelControl::setPitch(BGM 组, rate)  → 音乐跟着变速（音高随之升降，磁带效应）
//   ② 在 BGM 组上挂一个内置 Pitch Shifter DSP，把音高**补回来**：参数是**比率**
//      （0.5..2.0，1.0 = 不改变音高），所以要补的比率就是 1/rate，直接传。
//      ⚠ 参数在 FMOD 1.x 为**半音**（−12..12）；2.x 是 0.5..2.0 比率——勿按 1.x 文档写成 12·log2()。
//        本机权威证据是 DSP 自己的描述串（VA 0x1013d7711）：
//        "Pitch value.  0.5 to 2.0.  Default = 1.0. 0.5 = one octave down,
//         2.0 = one octave up.  1.0 does not change the pitch."
//      ⇒ 净效果 = 时长随速度、音高不变
//   ③ 延迟补偿：移调 DSP 有固有延迟 L（≈FFT 窗长），会让"听到的音乐"落后谱面 L。
//      在挂上 DSP / 重新挂时把通道位置**前移 rate·L**（一次性偏移）。
//
// 与 外部参考实现的差异（已知、有意）：
//   · 外部参考实现改的是**通道频率**并自建拉伸 DSP；这里改**组音高**并用内置移调器。
//   · 外部参考实现在拖拽/seek 后用**音频通道实时位置**重同步谱面钟（含 DSP 延迟、2 帧拉回）；
//     这里的延迟补偿是**一次性近似**，seek 后靠 tick 里的位置回退检测重补。
//   · 因此 ±20ms 级的 A/V 残差是这套实现的已知上限，不是 bug；要消掉需照搬 外部参考实现的重同步。
//
// 关键事实（出处 XRCProfile.h · FMOD 段）：
//   · BGM 走游戏的 "mainBGMGroup"，句柄存在 AudioProviderFMODiOS(player) + 0x18（ctor @sub_1008E0908）
//   · player 实例由 XRCPlayer 缓存（getpos hook）；通道表在 player+0x38（16B/项，句柄在 +8）
//   · FMOD system 指针在游戏全局 qword_10164E678（不需要落桩就能拿到）
//   · 内置 DSP 类型号**运行时探测**：枚举类型建 DSP → getInfo 读名字含 "Pitch" 者即移调器
//     （不写死常量，避免版本错配静默挂错 DSP）
#pragma once

#import <Foundation/Foundation.h>

// 应用倍率（幂等；rate≈1 时只复位音高、不挂 DSP）
void xrc_audio_speed_apply(double rate);

// 开关（配置/面板；默认开）。关 = 立刻把音高复位到 1.0 并停止跟随（DSP 留在链上但不移调）。
void xrc_audio_speed_set_enabled(BOOL on);
BOOL xrc_audio_speed_enabled(void);

// 低频调用（每帧/每次刷新）：内部去重 —— rate 或 player/组变了才动手。
// 覆盖三类变化：用户改速度、换歌（新 player）、组句柄首次出现。
void xrc_audio_speed_tick(void);

// 状态串（面板/日志诊断）
NSString *xrc_audio_speed_status(void);

// 当前已挂载 DSP 的输出延迟（真实毫秒），未挂载时为 0。
double xrc_audio_output_latency_ms(void);
