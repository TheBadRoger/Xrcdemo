// © 雾月星辰 & MLXC · github@XingChenRS
// XRCProbe.h — 运行时能力探针（内联组件回报机制）。
// 目的：把验证放到运行时。dylib 启动后主动核验：
//   1. 桩点是否真的注入（读被 patch 的入口字节 + trampoline 字节比对）
//   2. slot.orig 是否合理（= 入口 VA 重定位值）
//   3. vtable hook 是否真的装上（读回槽位，剥离 PAC 后比对函数指针）
// 结果写入日志（xrcdemo.log）+ 全局能力结构 g_caps，UI 按能力门控。
#pragma once

#include <stdint.h>
#include <stdbool.h>

typedef struct {
    bool stub_present;        // 入口字节 = 我方 patch
    bool stub_v2;             // trampoline = v2（含 MOV X3,X6；v1 缺 a6 转发）
    bool judge_handler_live;  // slot.orig 合理 且 slot.handler == 我方 handler
    bool gp_hook_live;        // GameScene vtable[103] == xrc_gameplay_update
    bool mtp_hook_live;       // MTP vtable[7] == 我方 getpos
} xrc_caps_t;

extern xrc_caps_t g_caps;

// 在全部 install 之后调用一次。逐项检查并打日志。
void xrc_probe_run(void);

// ---- 能力门面（UI 统一经此判断，不裸读 g_caps）----
bool xrc_cap_stub(void);      // 判定窗口可用：桩在位 且 judge handler 活
bool xrc_cap_gp(void);        // 跳转/循环可用：gp.update 钩子
bool xrc_cap_player(void);    // 时间轴/时长可用：MTP getpos 钩子
