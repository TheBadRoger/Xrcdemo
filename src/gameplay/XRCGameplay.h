// © 雾月星辰 & MLXC · github@XingChenRS
// XRCGameplay.h — gp.update hook + 谱面钟 retime + seek 平移 + A-B 循环。
#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <limits.h>
#include <stdatomic.h>

// vtable swizzle（PAC 感知）。
// 返回槽号，INT_MIN 失败。out_orig 为剥离签名的原函数指针。
int xrc_swizzle_vtable(uint64_t vtable_addr, uint64_t orig_fn_off, void *new_fn, void **out_orig);

// 安装 gameplay vtable hook（换速 retime）。
void xrc_gameplay_install_hooks(uint64_t image_base);

// gp.update 替换实现（self = GameScene；7.0 五参，同 6.13）。
void xrc_gameplay_update(void *self, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5);

// 当前 gameplay 实例（gp.update hook 缓存；循环/seek 平移用）。
extern _Atomic(void *) xrc_gp_instance;

// ---- deferred 操作状态机（UI 只登记，gp.update 循环内执行）----
// 原因：seek 读旧场景内部状态（sub_10091BBB8(v3[116])），
// UI 回调里 self 可能已过期 → UAF 崩溃。游戏循环内 self 保证存活。
typedef enum {
    XRC_OP_NONE = 0,
    XRC_OP_SEEK,          // 音频 seek + 谱面钟平移
    XRC_OP_SEEK_REPLAY,   // 重播定位：seek 平移
    XRC_OP_LOOP_REWIND,   // A-B 循环回到 A（seek 平移）
} xrc_op_t;

// UI 登记（非阻塞）：返回是否受理（状态机忙时拒绝）。
bool xrc_gameplay_request(xrc_op_t op, uint32_t param_ms);

// 当前 pending 状态（UI 显示/防重入用）。

// 读取谱面钟当前值（按 XRCProfile 的 clock 布局）。
int32_t xrc_chart_clock_ms(void *note_group);

// replay 走 seek 平移：xrc_gameplay_request(XRC_OP_SEEK_REPLAY/LOOP_REWIND)。
// A-B 循环状态：From/To（ms）与启用标志（ArcCreate 语义：To >= From+1000）。
bool xrc_loop_get_enabled(void);
void xrc_loop_set_range(uint32_t from_ms, uint32_t to_ms);
// 启用/停用循环（区间与启用分离；区间不完整时开启无效）。
void xrc_loop_set_enabled(bool on);
// 换歌（退出重进）→ 练习状态归零（清循环与 retry 回位）。retry 不触发此函数。
void xrc_loop_reset_all(void);
void xrc_loop_get_range(uint32_t *from_ms, uint32_t *to_ms);   // 任一可为 NULL
// gp.update 内部调用（每帧；回位监视与 deferred 操作）。
void xrc_loop_tick(void *gameplay, uint32_t pos_ms);

// 活场景指针（gp.update 缓存；0 = 不在对局）。
uint64_t xrc_gameplay_instance(void);
