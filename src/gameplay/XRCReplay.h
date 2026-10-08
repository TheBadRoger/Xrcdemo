// © 雾月星辰 & MLXC · github@XingChenRS
// XRCReplay.h — 回跳重播引擎。
//
// 功能语义：回跳到已游玩并判定过的谱面段落时，始终恢复音符；成绩是否清空由独立开关控制。
//
// 重置链的步骤顺序、阈值与守卫均为实测结论——改动前先核对行内注释。
#pragma once

#include <stdint.h>
#include <stdbool.h>

// 启动常驻线程（由 Tweak.x 在关卡安装完成后调用；线程定时唤醒，检测与落笔均在主队列）。
void xrc_replay_start(void);

// 回拖时是否重置成绩（默认关 = 保留成绩；不控制音符恢复）。
void xrc_replay_set_reset_score(bool on);
bool xrc_replay_reset_score_enabled(void);

// 已确认音频落位后的显式回退重置。必须在活场景的主线程调用。
void xrc_replay_seek(uint64_t scene, uint32_t target, uint32_t previous);
