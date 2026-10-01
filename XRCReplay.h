// © 雾月星辰 & MLXC · github@XingChenRS
// XRCReplay.h — 回跳重播引擎（由 plugin/PluginMain.m 功能主线折叠而来）。
//
// 功能语义：回跳到已游玩并判定过的谱面段落时，支持重新游玩该段，同时清空分数记录。
//
// 纪律（重构方案 §6/§12.1）：
//   · 原样搬迁、保序——真机验证过的阈值与守卫一律不动；
//   · 诊断外壳（差分探针/快照/宽转储）未随迁；plugin/ 目录在 P2 随热加载层一并删除。
#pragma once

#include <stdint.h>
#include <stdbool.h>

// 启动常驻线程（由 Tweak.x 在关卡安装完成后调用；线程只检出，落笔在主队列）。
void xrc_replay_start(void);

// 回跳重播总门（并入面板前的内部默认 = 关）。
void xrc_replay_set_enabled(bool on);
bool xrc_replay_enabled(void);
