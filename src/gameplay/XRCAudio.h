// 音乐倍速：FMOD 源时钟 + Signalsmith 实时频谱拉伸，保持音高。
// 已挂载的处理器在 1x 也保留固定延迟，seek/retry 清空历史缓冲。
#pragma once

#import <Foundation/Foundation.h>

// 应用倍率（幂等；首次非 1x 时挂载实时处理器）
void xrc_audio_speed_apply(double rate);

// 开关（配置/面板；默认开）。关 = 恢复 1x 并停止跟随，保留处理器延迟。
void xrc_audio_speed_set_enabled(BOOL on);
BOOL xrc_audio_speed_enabled(void);

// 低频调用（每帧/每次刷新）：内部去重 —— rate 或 player/组变了才动手。
// 覆盖三类变化：用户改速度、换歌（新 player）、组句柄首次出现。
void xrc_audio_speed_tick(void);

// 状态串（面板/日志诊断）
NSString *xrc_audio_speed_status(void);

// 当前已挂载 DSP 的输出延迟（真实毫秒），未挂载时为 0。
double xrc_audio_output_latency_ms(void);

// Acknowledges a plugin-owned seek without issuing another audio seek.
void xrc_audio_seek_finished(void);
double xrc_audio_effective_rate(void);
