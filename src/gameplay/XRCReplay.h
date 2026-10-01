// © 雾月星辰 & MLXC · github@XingChenRS
// XRCReplay.h — 回跳重播引擎。
//
// 功能语义：回跳到已游玩并判定过的谱面段落时，支持重新游玩该段，同时清空分数记录。
//
// 纪律：重置链的步骤顺序、阈值与守卫均为实测结论——改动前先读行内约束注释。
#pragma once

#include <stdint.h>
#include <stdbool.h>

// 启动常驻线程（由 Tweak.x 在关卡安装完成后调用；线程只检出，落笔在主队列）。
void xrc_replay_start(void);

// 回跳重播总门（默认关；面板开关驱动）。
void xrc_replay_set_enabled(bool on);
bool xrc_replay_enabled(void);
