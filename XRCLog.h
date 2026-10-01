// © 雾月星辰 & MLXC · github@XingChenRS
// XRCLog.h — 统一日志（级别 × 类别）+ 跨模块 UI 共享声明。
//
// 2026-09-28 重构背景：历史开发期把大量采集/打印混进了默认日志（逐请求、逐桩命中、
// 周期汇总、applog 转储…），日志臃肿到看不出重点。现在：
//   · 每条日志 = (类别, 级别)；默认只落 INFO 及以上，DEBUG 需显式开启（配置/策略/面板）。
//   · 类别可组合（位掩码）；`xrc_log(...)` 保留为兼容入口（INFO + 通用类）。
//   · 文件日志加 4MB 上限，超出自动截断（避免长跑把 Documents 撑爆）。
// 用法：
//   xrc_logi(XRCLC_NET, @"path=%@", p);     // 常规信息
//   xrc_logd(XRCLC_NET, @"rewritten → %@", u);// 调试细节（默认不落）
//   xrc_logw(XRCLC_DL,  @"status=%ld", code);  // 警告（默认落）
#pragma once

// 版本与构建戳：统一来源 XRCVersion.h（多处依赖其宏，含 UI 版本显示）。
#include "XRCVersion.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <stdint.h>
#include <stdatomic.h>

// ---------------- 级别 ----------------
typedef enum {
    XRCLL_ERROR = 0,
    XRCLL_WARN  = 1,
    XRCLL_INFO  = 2,   // 默认上限
    XRCLL_DEBUG = 3,
} xrc_log_level_t;

// ---------------- 类别（位掩码，可或）----------------
#define XRCLC_BOOT   (1u << 0)    // 启动 / 装配 / 补丁自检 / 配置
#define XRCLC_BRK    (1u << 1)    // BRK 桩注册与命中
#define XRCLC_NET    (1u << 2)    // 网络请求 / 改写 / 302
#define XRCLC_DL     (1u << 3)    // 下载栈（cocos/NSURLSession）
#define XRCLC_JUDGE  (1u << 4)    // 判定 / 改判 / 统计
#define XRCLC_AP     (1u << 5)    // 自动演奏
#define XRCLC_UI     (1u << 6)    // 面板 / 悬浮球 / 热加载
#define XRCLC_CB     (1u << 7)    // content bundle
#define XRCLC_OM     (1u << 8)    // OnlineManager / applog
#define XRCLC_PROBE  (1u << 9)    // 运行时探针 / 内存转储
#define XRCLC_MISC   (1u << 10)   // 其它
#define XRCLC_ALL    0x7FFu

// ---------------- 构建轴 ----------------
// Makefile/CI 以 -DXRC_DEBUG_BUILD=0|1 传入；缺省 0 = 发布安全（本地 make 经 Makefile 默认 1）。
// 发布构建下 xrc_logd 编译为空（调试格式串不进产物）；NSLog 镜像同样只在开发构建。
#ifndef XRC_DEBUG_BUILD
#  define XRC_DEBUG_BUILD 0
#endif

// ---------------- 写入 ----------------
void xrc_logl(uint32_t cat, xrc_log_level_t lvl, NSString *fmt, ...) NS_FORMAT_FUNCTION(3, 4);
void xrc_log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);   // 兼容：INFO + XRCLC_MISC

#define xrc_loge(cat, ...) xrc_logl((cat), XRCLL_ERROR, __VA_ARGS__)
#define xrc_logw(cat, ...) xrc_logl((cat), XRCLL_WARN,  __VA_ARGS__)
#define xrc_logi(cat, ...) xrc_logl((cat), XRCLL_INFO,  __VA_ARGS__)
#if XRC_DEBUG_BUILD
#define xrc_logd(cat, ...) xrc_logl((cat), XRCLL_DEBUG, __VA_ARGS__)
#else
#define xrc_logd(cat, ...) ((void)0)
#endif

// ---------------- 控制（配置 / 策略 / 面板）----------------
void      xrc_log_set_level(int level);      // 0..3；缺省 INFO(2)
int       xrc_log_level(void);
void      xrc_log_set_cats(uint32_t cats);   // 位掩码；缺省 XRCLC_ALL
uint32_t  xrc_log_cats(void);
// 常用组合：全开 DEBUG（诊断）/ 只开网络与下载（排查互联）/ 回到默认
void      xrc_log_preset_default(void);      // INFO + ALL
void      xrc_log_preset_verbose(void);      // DEBUG + ALL
void      xrc_log_preset_net(void);          // DEBUG + (NET|DL|BOOT)
const char *xrc_log_preset_name(void);       // 当前预设名（UI 显示用）

// ---------------- 跨模块 UI 共享（历史位置：原 XRCLog.h）----------------
@class XRCFloatButton;
extern XRCFloatButton *button;
@class XRCMenuBridge;
