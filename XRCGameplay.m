// © 雾月星辰 & MLXC · github@XingChenRS
// XRCGameplay.m — gp.update hook + 谱面钟 retime + seek（含循环）。
// seek 平移 = 音频 seek + 谱面钟 base 平移（判定比较 |note - (cur - base)|，
// 所以 base -= (cur - target) 即整体平移）。
// 循环/重打/换歌的玩法语义与三次程序化-retry 失败史见文件尾部
// 「循环 / 自动重建」区块的注释。

#import <Foundation/Foundation.h>
#import "XRCLog.h"    // xrc_log
#include <limits.h>
#include <sys/mman.h>
#include <errno.h>
#include <mach/vm_map.h>
#include <mach/mach_init.h>
#include "XRCGameplay.h"
#include "XRCRuntime.h"
#include "XRCProbe.h"
#include "XRCClock.h"
#include "XRCAudio.h"   // 音乐变速：每帧去重 tick（rate/组变了才动手）
#include "XRCPlayer.h"
#include "XRCProfile.h"

#if __has_include(<ptrauth.h>)
#  include <ptrauth.h>
#endif

_Atomic(void *) xrc_gp_instance = NULL;

static void (*s_orig_gp_update)(void *, uint64_t, uint64_t, uint64_t, uint64_t) = NULL;
static void *s_gp_last_clock = NULL;
static uint64_t s_gp_last_real_us = 0;
// retime 的两个分数余量：任何一环按整数截断，累积起来都会变成"越到后面越不同步"。
static uint64_t s_retime_rem_us = 0;    // 微秒→毫秒的余量
static double   s_retime_acc    = 0.0;  // (1−rate)·delta 的小数余量

// ---- deferred 操作状态机 ----
// 崩溃教训（2026-09-10 ips）：转场函数内部读 note_group+48（谱面钟），
// note_group 为 NULL 时 far=0x30 崩溃。所有执行路径必须先做**两级非空校验**：
//   scene != NULL && *(scene + XRC_GP_NOTEGROUP_OFF) != NULL
// 且请求在场景指针变化（换场/重开）时自动作废——旧场景的请求在新场景上无意义。
static _Atomic(uint32_t) s_pending_op    = XRC_OP_NONE;
static _Atomic(uint32_t) s_pending_ms    = 0;
static _Atomic(uint64_t) s_pending_scene = 0;   // 登记请求时的 scene 指针
static _Atomic(uint64_t) s_last_exec_us  = 0;   // 冷却起点（真实时间 us）
#define XRC_OP_COOLDOWN_US  (1500 * 1000ULL)    // seek/回位冷却 1.5s
#define XRC_OP_MAX_IDLE_US  (4000 * 1000ULL)    // 请求超过 4s 未执行 → 丢弃

bool xrc_gameplay_request(xrc_op_t op, uint32_t param_ms) {
    void *scene = atomic_load(&xrc_gp_instance);
    if (!scene) {
        xrc_logd(XRCLC_JUDGE, @"request rejected: no live scene");
        return false;
    }
    uint32_t cur = atomic_load(&s_pending_op);
    if (cur != XRC_OP_NONE) {
        xrc_logd(XRCLC_JUDGE, @"request rejected: pending op=%u", cur);
        return false;
    }
    atomic_store(&s_pending_scene, (uint64_t)scene);
    atomic_store(&s_pending_ms, param_ms);
    atomic_store(&s_pending_op, op);
    return true;
}

// 两级非空校验：返回可用 note_group，否则 NULL。
static void *s_valid_note_group(void *scene) {
    if (!scene) return NULL;
    void *ng = *(void **)((char *)scene + XRC_GP_NOTEGROUP_OFF);
    if (!ng) return NULL;
    // 谱面钟必须可读（转场内部第一步就读 +48）
    void *clk = *(void **)((char *)ng + XRC_CLOCK_IN_NOTEGROUP_OFF);
    if (!clk) return NULL;
    return ng;
}

// ---- retry 监视器 v2（2026-09-10，确定性检测）----
// 用户流程：勾选开关 → 开启循环或 seek 定位（capture=目标点）→ 游戏中暂停 → Retry。
// 判据（比时钟跳变确定得多）：**音频位置的帧间大回跳**——retry 重建场景会让音频
// 从曲尾/当前点回到曲首（jump < -10s），单点演奏不可能产生。
// 触发后写一个 pending seek（目标=capture）；deferred 状态机在**新场景**的下一帧
// 才执行（旧场景已被 retry 销毁，同一帧不可用）。执行后解除（一次性）。
// 阈值说明：retry/换歌重建后音频必然从曲中/曲尾回到 0ms 附近，单点演奏的
// 帧间正常波动不可能超过 10 秒 → -10s 是"重建类事件"的可靠判据。
#define XRC_RETRY_AUDIO_JUMP_MS  (-10000)   // 音频帧间回跳阈值
static _Atomic(bool)     s_cap_valid = false;   // 音频基准是否已建立
static int32_t           s_prev_audio_ms = -1;
// v8.55：**自家 seek 标记**。帧内时序（见下）：s_exec_pending 下完 seek 后，音频位置
// 要到下一帧才真的落位（真机实测："pos 25045 -> 25045" 立即读是旧值）⇒ watcher 在
// 下一帧必然看到一次大回落。此前这被当成「外部 retry」：循环开着时会**再补一次 seek**
// （真机 AB 循环下成对的重置 #6→#7 / #8→#9 的头号嫌疑；循环关着则打一串
// "audio jump -N ignored" 噪声——那正是回跳轮次里每个 seek 后面跟一行 log 的来源）。
static _Atomic(uint64_t) s_own_seek_us = 0;
#define XRC_OWN_SEEK_WIN_US  (3000 * 1000ULL)   // 自家 seek 的豁免窗：3s

// 帧内调用（note_group 有效时）：音频位置回跳检测。
static void s_retry_watch_tick(void) {
    // v9.0.0：监视常开（回位点由"循环是否开启"在触发时刻决定，无 capture 状态）。
    int32_t pos = (int32_t)xrc_player_position_ms();
    if (pos < 0) return;
    if (!atomic_load(&s_cap_valid)) {
        s_prev_audio_ms = pos;
        atomic_store(&s_cap_valid, true);
        return;
    }
    int32_t jump = pos - s_prev_audio_ms;
    s_prev_audio_ms = pos;
    if (jump < XRC_RETRY_AUDIO_JUMP_MS) {
        // v8.55：先问「这一跳是不是我们自己 seek 出来的」——是则只消账，不动作。
        uint64_t own = atomic_load(&s_own_seek_us);
        if (own && xrc_real_now_us() - own < XRC_OWN_SEEK_WIN_US) {
            atomic_store(&s_own_seek_us, 0);
            xrc_logd(XRCLC_JUDGE, @"audio jump %d = 自家 seek（豁免，不外补）", jump);
            return;
        }
        // 手动 retry（或异常回跳）回位：**仅循环开启时**回 A 点。
        // 未开循环 = 不干预（用户要求：不得锁到任何残留位置——v8.9.9 之前的
        // capture 残留值曾把进度锁到随机位置，已彻底移除该数据流）。
        uint32_t a = 0, b = 0;
        xrc_loop_get_range(&a, &b);
        if (xrc_loop_get_enabled() && b > a + 1000) {
            if (xrc_gameplay_request(XRC_OP_SEEK, a)) {
                xrc_logd(XRCLC_JUDGE, @"retry detected (audio jump %d) -> seek loop A %u", jump, a);
            }
        } else {
            xrc_logd(XRCLC_JUDGE, @"audio jump %d ignored (loop off)", jump);
        }
    }
}

// ---- v8.56：冻结式 seek（外部参考实现统一时钟模型落地）----
// 设计全链（含反编译证据）：内部设计纪要（2026-10-01，离线记录）
// 事务：暂停音频 → 音频 seek → 钟**绝对写** → 重置链在冻结窗内跑完（世界冻住：无声 + 钟被
// 每帧钉住，无竞态、无“卡顿”感知）→ 插件经 dlsym xrc_freeze_end 收口 → 以实测音频位置再写
// 一次 → 3 帧收敛窗 → 恢复音频。绝对写取代旧的 base 平移 ⇒ 引擎窗口期改写字段不再能造成
// 漂移（D4 双回跳 / D5 卡死 的正解）；冻结期 stall 监视豁免。
#define XRC_FRZ_OFF     0
#define XRC_FRZ_FROZEN  1
#define XRC_FRZ_RESYNC  2
#define XRC_FRZ_MAX_US   (1500 * 1000ULL)   // 1.5s 强制解冻兜底（**按时间**——v8.56 的帧数兜底
                                            // 被真机否决：引擎追赶循环一次可调数百遍 gp.update，
                                            // "90 帧"194ms 就烧完）
#define XRC_RESYNC_US    (60 * 1000ULL)     // 收敛窗 ≈60ms（外部参考实现=2 帧@60fps≈33ms，多留余量）
static _Atomic(int) s_frz_state  = 0;
static _Atomic(int) s_frz_target = 0;
static _Atomic(uint64_t) s_frz_deadline_us = 0;

static inline int32_t xrc_sat_add32(int32_t a, int32_t b) {
    int64_t v = (int64_t)a + b;
    if (v > 2147483647LL) return 2147483647;
    if (v < (-2147483647LL - 1)) return (-2147483647 - 1);
    return (int32_t)v;
}

// v8.56 的 xrc_clock_write_abs（照抄 外部参考实现直接写 +16/+32/+52）已被真机否决 ——
// 事故：2026-10-01 23:10，v8.56 两次回跳均立刻「收歌进结算」。日志物证：
//   ◎G t=310174073 clk=49986/81/f1（谱面钟读成 3.1 亿 ms ≈ 3.6 天）
// 机制：这些字段是引擎**自己连续时钟域**（真机 base≈310,164,256ms，与系统 uptime 176M
// **不同域**——含睡眠计时）的时间戳；跨域直接写触发引擎重归一化，把 (base, +32) 拆散
// ⇒ 读法爆炸 ⇒ 超过曲长 ⇒ 引擎立即收歌。**教训：+3000 常数背后是整个域约定，不可只抄数字。**
// ⇒ v8.57：全部定位退回 **base 平移**——本机唯一验证过（数百轮）的写。它天然域无关：
// 只加「同域两个量的差」，不引入任何跨域常数。
static void xrc_clock_shift_to(void *note_group, int32_t target) {
    if (!note_group) return;
    void *clk = *(void **)((char *)note_group + XRC_CLOCK_IN_NOTEGROUP_OFF);
    if (!clk) return;
    int32_t cur = xrc_chart_clock_ms(note_group);
    int32_t *base_off = (int32_t *)((char *)clk + XRC_CLK_BASE_OFF);
    *base_off = xrc_sat_add32(*base_off, xrc_sat_add32(cur, -target));
}

// 冻结窗收口（插件重建链末尾经 dlsym 调用；时间兜底在 s_frz_tick）。
// 顺序照搬 外部参考实现 finish_scrub：先以当前（暂停中的）落位平移一次 → 恢复音频 → 进收敛窗。
// v8.58：落位守卫**也加在这里**——真机事故（23:22:42）：暂停期间游戏不调 getpos，位置缓存
// 还是旧值（61952 vs target 44992），收口把这笔 stale 平移进钟 ⇒ 时钟弹回高位 ⇒ 循环 tick
// 二度触发 + 收敛窗掰回的一截又被当成新回跳 ⇒ **AB 循环多跳一次**。现在超窗就不平移，
// 交给收敛窗（音频恢复后缓存随即刷新）落位。
void xrc_freeze_end(void) {
    if (atomic_load(&s_frz_state) != XRC_FRZ_FROZEN) return;   // 幂等
    void *scene = atomic_load(&xrc_gp_instance);
    void *ng = scene ? *(void **)((char *)scene + XRC_GP_NOTEGROUP_OFF) : NULL;
    int32_t tgt = atomic_load(&s_frz_target);
    if (ng) {
        int32_t pos = (int32_t)xrc_player_position_ms();
        if (pos < 0) pos = 0;
        int32_t d = pos - tgt;
        if (d < 0) d = -d;
        if (d <= 5000) {
            xrc_clock_shift_to(ng, pos);
        } else {
            xrc_logd(XRCLC_JUDGE, @"冻结窗收口：pos=%d 未落位（target=%d）——本次不平移，交给收敛窗", pos, tgt);
        }
    }
    xrc_player_pause(false);
    xrc_clock_freeze_dec();
    atomic_store(&s_frz_deadline_us, xrc_real_now_us() + XRC_RESYNC_US);
    atomic_store(&s_frz_state, XRC_FRZ_RESYNC);
    xrc_logd(XRCLC_JUDGE, @"冻结窗收口：恢复音频，进入收敛窗");
}

// 每帧（gp.update，主线程）：冻结窗钉钟 / 收敛窗按实测音频位置拉回。
static void s_frz_tick(void *note_group) {
    int st = atomic_load(&s_frz_state);
    if (st == XRC_FRZ_OFF) return;
    if (!note_group) {
        xrc_player_pause(false);
        xrc_clock_freeze_dec();
        atomic_store(&s_frz_state, XRC_FRZ_OFF);
        return;
    }
    uint64_t now_us = xrc_real_now_us();
    if (st == XRC_FRZ_FROZEN) {
        xrc_clock_shift_to(note_group, atomic_load(&s_frz_target));   // 钉住
        if (now_us > atomic_load(&s_frz_deadline_us)) {
            xrc_logd(XRCLC_JUDGE, @"冻结窗：**兜底解冻**（超 %.1fs 未见重置收口）",
                     (double)XRC_FRZ_MAX_US / 1e6);
            xrc_freeze_end();
        }
    } else if (st == XRC_FRZ_RESYNC) {
        int32_t pos = (int32_t)xrc_player_position_ms();
        if (pos < 0) pos = 0;
        // 未落位守卫：音频 seek 失败/未生效时 pos 仍是旧位置 —— 平移下去会把钟拉回旧处，
        // 反而制造一次假回跳。仅当 pos 已接近本次目标（±5s）才跟随。
        int32_t tgt = atomic_load(&s_frz_target);
        int32_t dpos = pos - tgt;
        if (dpos < 0) dpos = -dpos;
        if (dpos <= 5000) xrc_clock_shift_to(note_group, pos);
        // v8.58：软截止（60ms）后**落位即收**（≤300ms 差）；未落位最多再等 600ms 兜底。
        uint64_t ddl = atomic_load(&s_frz_deadline_us);
        if (now_us > ddl && (dpos <= 300 || now_us > ddl + 600000ULL)) {
            s_prev_audio_ms = (int32_t)xrc_player_position_ms();
            atomic_store(&s_cap_valid, true);
            atomic_store(&s_frz_state, XRC_FRZ_OFF);
            xrc_logd(XRCLC_JUDGE, @"收敛窗结束：pos=%d（target=%d，%s）", pos, tgt,
                     dpos <= 300 ? "已落位" : "超时未落位");
        }
    }
}

// 在游戏循环内执行 pending（self = 当前活场景）。
static void s_exec_pending(void *self) {
    uint32_t op = atomic_load(&s_pending_op);
    if (op == XRC_OP_NONE) return;

    uint64_t now = xrc_real_now_us();

    // 场景变更 → 丢弃陈旧请求（旧场景的 seek 在新场景无意义）
    uint64_t req_scene = atomic_load(&s_pending_scene);
    if (req_scene != (uint64_t)self) {
        atomic_store(&s_pending_op, XRC_OP_NONE);
        xrc_logd(XRCLC_JUDGE, @"pending op=%u dropped (scene changed %llx -> %p)", op, req_scene, self);
        return;
    }

    uint64_t last = atomic_load(&s_last_exec_us);
    if (last && now - last < XRC_OP_COOLDOWN_US) return;  // 冷却中

    // 过期丢弃
    static uint64_t s_req_time = 0;
    if (s_req_time == 0) s_req_time = now;
    if (now - s_req_time > XRC_OP_MAX_IDLE_US) {
        atomic_store(&s_pending_op, XRC_OP_NONE);
        s_req_time = 0;
        return;
    }

    uint32_t ms = atomic_load(&s_pending_ms);

    // 执行前最终校验（崩溃 guard）
    void *note_group = s_valid_note_group(self);
    if (!note_group) {
        xrc_logd(XRCLC_JUDGE, @"pending op=%u aborted: note_group/clock null (scene=%p)", op, self);
        atomic_store(&s_pending_op, XRC_OP_NONE);
        return;
    }

    atomic_store(&s_pending_op, XRC_OP_NONE);   // 先清（防执行内重入）
    atomic_store(&s_last_exec_us, now);
    s_req_time = 0;

    if (op == XRC_OP_SEEK || op == XRC_OP_SEEK_REPLAY || op == XRC_OP_LOOP_REWIND) {
        int32_t cur_ms = xrc_chart_clock_ms(note_group);

        /* v8.59：前导期/加载中的 seek **整笔丢弃**。真机 23:40:11 实证：cur=-3000（新场景
           加载中）时执行 seek ⇒ 半生效 + 场景随即重建 ⇒ 卡死监视误判、1.5s 一次强拉、
           垃圾回落——一整分钟的乱流都从这一笔长出来。前导期"找位置"本身无意义（歌还没
           开始）⇒ 丢弃是正确语义。**D2（前导 seek 要生效）就此作废**：不要这个行为。 */
        if (cur_ms < 0) {
            xrc_logd(XRCLC_JUDGE, @"seek 丢弃：前导/加载中（cur=%d ms=%u）", cur_ms, ms);
            return;
        }

        // v8.56① 去抖（外部参考实现 PRAC_7seek_to 的 16ms 窗）：同目标重复请求合并，防连击风暴。
        {
            static int32_t  s_dbd_ms = 0;
            static uint64_t s_dbd_us = 0;
            uint64_t nowu = xrc_real_now_us();
            int32_t d = (int32_t)ms - s_dbd_ms;
            if (d < 0) d = -d;
            if (op == XRC_OP_SEEK && d < 16 && nowu - s_dbd_us < 500000ULL) {
                xrc_logd(XRCLC_JUDGE, @"seek debounced: ms=%u（与上次目标同区，16ms 窗）", ms);
                return;
            }
            s_dbd_ms = (int32_t)ms;
            s_dbd_us = nowu;
        }
        // v8.56② 曲长钳制（外部参考实现同款时长守卫）
        {
            uint32_t dur = xrc_player_song_length_ms();
            if (dur && ms > dur) ms = dur;
        }
        // v8.56③ 方向判定：回退幅度超过快路径检测阈（300ms）⇒ 预期触发回跳重置 ⇒ 全程冻结。
        int frz = ((cur_ms - (int32_t)ms) > 300);

        // 音频 seek（player 可能已换歌，重新取）
        void *player = xrc_player_get();
        if (!player) frz = 0;    // v8.56：没有播放器就不进冻结窗（否则 freeze_inc/dec 配不平）
        if (player) {
            int32_t pos_before = (int32_t)xrc_player_position_ms();
            if (frz) {
                xrc_clock_freeze_inc();          // 停 retime（它写 base）
                xrc_player_pause(true);          // v8.56：音频暂停（外部参考实现拖动暂停的最小化版）
            }
            xrc_player_seek_ms(player, ms);
            /* v8.55：给 watcher 记一笔「这一跳是我们自己干的」（音频下一帧才落位，
               落位时 watcher 必然看到大回落 —— 见 s_own_seek_us 注释）。 */
            atomic_store(&s_own_seek_us, xrc_real_now_us());
            int32_t pos_after = (int32_t)xrc_player_position_ms();
            xrc_logd(XRCLC_JUDGE, @"audio seek: target=%u, pos %d -> %d（%s）", ms, pos_before, pos_after,
                     frz ? "回退→冻结" : "前进→导航");
        } else {
            xrc_logd(XRCLC_JUDGE, @"audio seek SKIPPED: player null (target=%u)", ms);
        }
        // v8.57：定位退回 **base 平移**（唯一验证过的写；v8.56 的直接字段写被真机否决，
        // 见 xrc_clock_shift_to 注释）。前导期在上面的 v8.59 闸门已整笔丢弃 ⇒ 这里 cur≥0。
        xrc_clock_shift_to(note_group, (int32_t)ms);
        s_gp_last_real_us = 0;

        if (frz) {
            atomic_store(&s_frz_target, (int32_t)ms);
            atomic_store(&s_frz_deadline_us, xrc_real_now_us() + XRC_FRZ_MAX_US);
            atomic_store(&s_frz_state, XRC_FRZ_FROZEN);
            xrc_logd(XRCLC_JUDGE, @"seek executed: ms=%u (cur was %d)｜冻结窗开（等重置链收口/1.5s 兜底）",
                     ms, cur_ms);
        } else {
            // 前进/近距：纯导航 —— 无冻结无收敛窗（绝对写已就位；音频将精确落在 target）。
            xrc_logd(XRCLC_JUDGE, @"seek executed: ms=%u (cur was %d)｜导航", ms, cur_ms);
        }
    }

    if (op == XRC_OP_SEEK_REPLAY || op == XRC_OP_LOOP_REWIND) {
        // v8.56：音频基准不在这里对齐（seek 后立即读是旧值）；冻结窗/收敛窗收口时已对齐。
        xrc_logd(XRCLC_JUDGE, @"replay executed via seek (op=%u)", op);
    }
}

// ---- vtable swizzle（PAC 感知）----
int xrc_swizzle_vtable(uint64_t vtable_addr, uint64_t orig_fn_off, void *new_fn, void **out_orig) {
    extern uint64_t xrc_image_base(void);
    uint64_t base = xrc_image_base();
    if (!base) return INT_MIN;
    uint64_t target = base + orig_fn_off;
    void **vt = (void **)vtable_addr;
    // 同 6.13：地址合理性检查 + [-4, 64) 槽搜索
    if ((uintptr_t)vt < 0x100000000ULL || ((uintptr_t)vt & 7) != 0) return INT_MIN;
    for (int i = 0; i < 200; i++) {
        void *cur = vt[i];
        if (!cur) continue;
#if __has_feature(ptrauth_calls)
        void *stripped = ptrauth_strip(cur, ptrauth_key_asia);
#else
        void *stripped = cur;
#endif
        if ((uint64_t)stripped != target) continue;
        uintptr_t page = (uintptr_t)&vt[i] & ~(uintptr_t)0x3FFF;
        bool wrote = false;
        if (mprotect((void *)page, 0x4000, PROT_READ | PROT_WRITE) == 0) {
            wrote = true;
        } else {
            kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)page, 0x4000,
                                          0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
            wrote = (kr == KERN_SUCCESS);
        }
        if (!wrote) return INT_MIN;
        if (out_orig) *out_orig = stripped;
#if __has_feature(ptrauth_calls)
        void *signed_new = ptrauth_sign_unauthenticated(new_fn,
                              ptrauth_key_asia,
                              ptrauth_blend_discriminator(&vt[i], 0));
        vt[i] = signed_new;
#else
        vt[i] = new_fn;
#endif
        mprotect((void *)page, 0x4000, PROT_READ);
        return i;
    }
    return INT_MIN;
}

// ---- 谱面钟 ----
int32_t xrc_chart_clock_ms(void *note_group) {
    if (!note_group) return -1;
    void *clk = *(void **)((char *)note_group + XRC_CLOCK_IN_NOTEGROUP_OFF);
    if (!clk) return -1;
    if (*(uint8_t *)((char *)clk + XRC_CLK_FLAG45_OFF) & 1)
        return *(int32_t *)((char *)clk + XRC_CLK_ALT_START_OFF) - *(int32_t *)((char *)clk + XRC_CLK_BASE_OFF);
    int32_t v = *(int32_t *)((char *)clk + XRC_CLK_CUR_OFF);
    int32_t off = (v <= 0) ? XRC_CLK_NEG_LEAD_MS : 0;
    return v - *(int32_t *)((char *)clk + XRC_CLK_BASE_OFF) + off;
}

// ---- gp.update retime（6.13 语义）----
static void s_gp_retime_logic_clock(void *note_group) {
    if (!note_group) return;
    if (xrc_clock_freeze_count() > 0) return;
    void *clk = *(void **)((char *)note_group + XRC_CLOCK_IN_NOTEGROUP_OFF);
    if (!clk) return;
    uint64_t now_us = xrc_real_now_us();
    if (!now_us) return;
    if (clk != s_gp_last_clock || s_gp_last_real_us == 0 || now_us <= s_gp_last_real_us) {
        s_gp_last_clock = clk;
        s_gp_last_real_us = now_us;
        s_retime_rem_us = 0;      // 换钟/时间回退：余量作废，否则会把旧增量带进新歌
        s_retime_acc = 0.0;
        return;
    }
    uint64_t delta_us = now_us - s_gp_last_real_us;
    if (delta_us > 200000ULL) delta_us = 200000ULL;
    s_gp_last_real_us = now_us;
    // 微秒→毫秒也要带余量：60fps 的 16667µs 直接截成 16ms，每秒少 40µs×60 = 2.4ms 基准。
    uint64_t acc_us = delta_us + s_retime_rem_us;
    int32_t delta_ms = (int32_t)(acc_us / 1000ULL);
    s_retime_rem_us = acc_us % 1000ULL;
    if (delta_ms <= 0) return;
    double rate = xrc_clock_get_rate();
    int32_t adjust = 0;
    if (rate < 0.999 || rate > 1.001) {
        // 分数部分必须累积：逐帧截断是有系统性偏差的。
        // 60fps 时 delta_ms 被截成 16（真值 16.67），rate=0.8 每帧要补 3.33ms，
        // 截断后只补 3ms —— 每帧少 0.33ms，一秒就是 20ms，三分钟的歌累计漂 3.6 秒。
        // 这种"越到后面越不同步"正是它，而不是别的。
        s_retime_acc += (1.0 - rate) * (double)delta_ms;
        adjust = (int32_t)s_retime_acc;
        s_retime_acc -= (double)adjust;
    }
    if (adjust == 0) return;
    int32_t *base_off = (int32_t *)((char *)clk + XRC_CLK_BASE_OFF);
    int64_t after = (int64_t)(*base_off) + (int64_t)adjust;
    if (after > INT_MAX) after = INT_MAX;
    if (after < INT_MIN) after = INT_MIN;
    *base_off = (int32_t)after;
}

uint64_t xrc_gameplay_instance(void) { return (uint64_t)atomic_load(&xrc_gp_instance); }

// ---- 音画倍率自测（1 Hz，只读）----
// 为什么必须量：变速有**两条独立通路** —— ① gettimeofday fishhook 把"游戏看到的
// 墙上时间"按 rate 缩放（管视觉/Cocos 逻辑），② gp.update 里对谱面钟 base_off 的
// 累积 retime（管音符时序）。如果游戏自身的钟也走被 warp 的时间域，两者就会**叠加**，
// 谱面实际倍率变成 2·rate−1，而音频（FMOD 自有音频钟）仍是 rate —— 这就是
// "音画倍率不同步"。日志里把 设定值 / 谱面实际斜率 / 音频实际斜率 一起打出来，
// 一眼就能看出是哪条路多算或少算，不必再猜。
static void s_rate_probe_tick(void *note_group) {
    static uint64_t last_us = 0;
    static int32_t  last_chart = 0;
    static uint32_t last_chan = 0;
    static int      have = 0;
    uint64_t now = xrc_real_now_us();
    if (!now || now - last_us < 1000000ULL) return;
    int32_t  chart = xrc_chart_clock_ms(note_group);
    uint32_t chan  = xrc_player_position_ms();
    double   rate  = xrc_clock_get_rate();
    if (have && chart >= 0 && last_chart >= 0) {
        double dt     = (double)(now - last_us) / 1000000.0;
        double dchart = (double)(chart - last_chart) / 1000.0;
        double dchan  = (double)((int32_t)chan - (int32_t)last_chan) / 1000.0;
        xrc_logd(XRCLC_BOOT, @"[rate] set=%.3f 谱面×%.3f 音频×%.3f (Δt=%.2fs)",
                 rate, dchart / dt, dchan / dt, dt);
    }
    last_us = now; last_chart = chart; last_chan = chan; have = 1;
}

void xrc_gameplay_update(void *self, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5) {
    if (self) {
        atomic_store(&xrc_gp_instance, self);
        void *note_group = *(void **)((char *)self + XRC_GP_NOTEGROUP_OFF);
        if (note_group) {
            s_gp_retime_logic_clock(note_group);
            s_rate_probe_tick(note_group);      // 音画倍率自测（1 Hz，只读）
            int32_t pos = xrc_chart_clock_ms(note_group);
            // v8.58：冻结/收敛窗内钟不是真实播放时间（钉住/落位中）——循环 tick 抑制，
            // 防事务中间态二次触发回跳（真机 23:22:42：收口缺守卫把钟弹回旧位 → 循环二跳）。
            if (pos > 0 && !atomic_load(&s_frz_state)) xrc_loop_tick(self, (uint32_t)pos);
        }
        s_exec_pending(self);   // deferred 操作（seek/循环回位）在活场景循环内执行

        // retry 监视 v2（音频回跳）；循环卡死恢复保留。
        if (note_group) {
            s_frz_tick(note_group);   // v8.56：冻结窗钉钟 / 收敛窗按实测音频位置拉回
            s_retry_watch_tick();
            // 循环卡死恢复：pos 停滞超 1.5s 且位于 [A,B) 内 → 强制回 A
            int32_t pos = xrc_chart_clock_ms(note_group);
            static int32_t s_stall_pos = 0;
            static int32_t s_stall_audio_prev = -1;
            static uint64_t s_stall_audio_us = 0;    /* v8.59：音频最近一次变化的时间 */
            static uint64_t s_stall_since = 0;
            uint64_t now_us = xrc_real_now_us();
            {
                int32_t apos = (int32_t)xrc_player_position_ms();
                if (apos != s_stall_audio_prev) { s_stall_audio_prev = apos; s_stall_audio_us = now_us; }
            }
            if (atomic_load(&s_frz_state)) {
                // v8.56：冻结窗内钟是**故意钉住**的（停滞是预期行为）——监视豁免，
                // 防冻结满 1.5s 时误触发一次「卡死回绕」。
                s_stall_pos = pos;
                s_stall_since = now_us;
            } else if (pos != s_stall_pos) {
                s_stall_pos = pos;
                s_stall_since = now_us;
            } else if (now_us - s_stall_audio_us > 700000ULL) {
                // v8.59：钟静止但**音频 ≥0.7s 没动** ⇒ 暂停菜单/加载冻结，不是卡死——不计时。
                // 真机 23:40：加载中钟停在 24000，监视器每 1.5s 强拉一次、连拉 4 次。
                // （判据必须用「音频最后一次变化距今」，不能用帧间比较——音频缓存本身就是
                //   跳变更新的，帧间比较会把真实卡死误判成暂停、计时器永远攒不起来。）
                s_stall_since = now_us;
            } else if (s_stall_since && now_us - s_stall_since > 1500000ULL) {
                uint32_t a = 0, b = 0;
                xrc_loop_get_range(&a, &b);
                if (xrc_loop_get_enabled() && pos < (int32_t)b - 200) {
                    if (xrc_gameplay_request(XRC_OP_LOOP_REWIND, a))
                        xrc_logd(XRCLC_JUDGE, @"loop stall at %d -> forced rewind to %u", pos, a);
                }
                s_stall_since = now_us;
            }
        }
    }
    // 音乐变速（2026-09-29）：低频去重 tick —— 速度变了/换歌了/组刚建才动作。
    // 放这里是因为 gp.update 是唯一"进对局后每帧都在跑"的点，面板不开时也有效。
    @try { xrc_audio_speed_tick(); } @catch (NSException *e) {}
    if (s_orig_gp_update) s_orig_gp_update(self, a2, a3, a4, a5);
}

void xrc_gameplay_install_hooks(uint64_t image_base) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!g_xrc.gp_vtable || !g_xrc.gp_update) {   // 锚点未就绪 → 降级（2026-09-28：不再静默）
            xrc_logd(XRCLC_JUDGE, @"gp hooks skipped: anchor not ready (vtable=%llx update=%llx)",
                    g_xrc.gp_vtable, g_xrc.gp_update);
            return;
        }
        int slot = xrc_swizzle_vtable(g_xrc.gp_vtable,
                                      g_xrc.gp_update - g_xrc.image_base,
                                      (void *)xrc_gameplay_update,
                                      (void **)&s_orig_gp_update);
        if (slot != INT_MIN) xrc_logd(XRCLC_JUDGE, @"gp.update vtable installed slot=%d", slot);
    });
}


#pragma mark - 循环 / 自动重建（玩法语义说明）

/* ───────────────────────── 数据流总览（v9.0.0） ─────────────────────────
 *
 * 循环区间 A/B：仅由面板「起点」/「终点」按钮写入；仅由面板「重置循环」
 *   按钮清除（xrc_loop_reset_all）。**没有任何自动清除路径**——v8.9.6-9
 *   的"换歌/曲长归零自动清"已全部下线：真机证明 retry 重建同样会重置
 *   曲长（len=143896->0），自动判据必然误伤（用户报告"retry 清循环"）。
 *
 * 循环开关：面板「循环 开/关」（区间完整才允许开启）。
 *
 * 到 B 点（循环开）：deferred seek 平移回 A（练习定位语义：已判音符不
 *   重现、计分不回滚；不触碰游戏状态机，无卡死风险）。
 *
 * 手动 Retry（游戏原生重建，安全）：重建后音频回跳（>-10s）被检测 →
 *   **仅当循环开启**时 seek 回 A；未开循环则不干预（修掉 v8.9.9 以前
 *   capture 残留值把进度锁到随机位置的 bug）。
 *
 * 程序化 retry：三次尝试全部失败且最后一次污染 action 队列致卡死，
 *   永久放弃（全过程见历史记录 v8.9.6/7/8 与 replay 笔记 §11）。
 * ──────────────────────────────────────────────────────────────────────── */

/*
 * 玩法定义与实现定案（2026-09-10 v8.9.9）：
 *
 * 【A-B 循环练习】
 *   用户流程：播放到起点按「起点」→ 播放到终点按「终点」→ 开「循环」。
 *   到 B 点 → deferred seek 平移回 A（音频 seek + 谱面钟 base 平移）。
 *   语义：练习定位——已判音符不重现、计分不回滚（v8.9.5 实测稳定，不触
 *   碰游戏状态机、无卡死风险）。
 *
 * 【完整重打（音符重现）】
 *   用户暂停菜单自行 Retry（游戏原生重建链，安全），重建后音频回跳检测
 *   随即把进度拉回 A（该链 v8.9.5/6 实测有效：retry detected -> seek A）。
 *
 * 【程序化 retry（已放弃，禁止复活）】
 *   v8.9.6 直调 triggerAction(13) → 被静默忽略（Retry 回调首校验
 *   PauseLayer+0x298==1，新层未置位）；v8.9.7 建暂停层+setup → 仍忽略；
 *   v8.9.8 建层+置 0x298+triggerAction → 仍忽略，且 9 次尝试把 action
 *   记录塞进 GameModel 队列，污染状态致手动 retry 卡死转场界面。
 *   结论：retry 与暂停流程深度耦合，外部驱动需动内部状态，风险不可控。
 *   研究记录见 XRCProfile.h 的 retry 触发链注释段。
 *
 * 【退出重进 vs retry】
 *   换歌/退出重进 = 播放器实例更换或曲长归零（见面板 watcher 判据）→
 *   xrc_loop_reset_all() 清空练习状态。retry = 同一播放器、场景重建 →
 *   状态保留，正好用于续练。
 */

static _Atomic(bool) s_loop_enabled = false;
static _Atomic(uint32_t) s_loop_a = 0;
static _Atomic(uint32_t) s_loop_b = 0;

bool xrc_loop_get_enabled(void) { return atomic_load(&s_loop_enabled); }
void xrc_loop_set_range(uint32_t a_ms, uint32_t b_ms) {
    // 2026-09-10 交互重构：设定区间**不再自动启用**（面板流程：设起点→设终点→开循环）。
    // 区间合法性（b >= a+1000）在 tick 与 set_enabled 时检查。
    atomic_store(&s_loop_a, a_ms);
    atomic_store(&s_loop_b, b_ms);
}
void xrc_loop_set_enabled(bool on) {
    uint32_t a = atomic_load(&s_loop_a), b = atomic_load(&s_loop_b);
    if (on && b <= a + 1000) return;   // 区间不完整不允许开启
    atomic_store(&s_loop_enabled, on);
    xrc_logd(XRCLC_JUDGE, @"loop %s (A=%u B=%u)", on ? "ON" : "OFF", a, b);
}
// 换歌/退出重进 = 练习状态归零（用户定义：只要退出重进就视作换歌，哪怕同一首）。
// 触发链：Tweak.x 0.5s 轮询（player 指针变化）+ 面板 tick watcher（指针/曲长归零）。
// retry 不走这里：同一播放器实例内的场景重建，状态必须保留才能续练。
void xrc_loop_reset_all(void) {
    atomic_store(&s_loop_enabled, false);
    atomic_store(&s_loop_a, 0);
    atomic_store(&s_loop_b, 0);
    xrc_logd(XRCLC_JUDGE, @"loop range reset (manual)");
}
void xrc_loop_get_range(uint32_t *from_ms, uint32_t *to_ms) {
    if (from_ms) *from_ms = atomic_load(&s_loop_a);
    if (to_ms)   *to_ms   = atomic_load(&s_loop_b);
}
void xrc_loop_tick(void *gameplay, uint32_t pos_ms) {
    if (!atomic_load(&s_loop_enabled)) return;
    uint32_t a = atomic_load(&s_loop_a), b = atomic_load(&s_loop_b);
    if (b <= a + 1000) return;
    if (pos_ms >= b) {
        if (xrc_gameplay_request(XRC_OP_LOOP_REWIND, a))
            xrc_logd(XRCLC_JUDGE, @"loop rewind at %u -> %u (seek shift)", pos_ms, a);
    }
}

