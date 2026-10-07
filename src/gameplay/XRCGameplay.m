// © 雾月星辰 & MLXC · github@XingChenRS
// XRCGameplay.m — gp.update hook + 谱面钟 retime + seek（含循环）。
// seek 平移 = 音频 seek + 谱面钟 base 平移（判定比较 |note - (cur - base)|，
// 所以 base -= (cur - target) 即整体平移）。
// 循环 / 重打 / 换歌的玩法语义见文件尾部「循环 / retry 回位」区块的注释。

#import <Foundation/Foundation.h>
#import "XRCLog.h"    // xrc_log
#include <limits.h>
#include <objc/runtime.h>
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
#include "XRCReplay.h"
#include "XRCSeekMath.h"
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
// 转场函数内部读 note_group+48（谱面钟），note_group 为 NULL 时 far=0x30 崩溃。
// 所有执行路径必须先做**两级非空校验**：
//   scene != NULL && *(scene + XRC_GP_NOTEGROUP_OFF) != NULL
// 且请求在场景指针变化（换场/重开）时自动作废——旧场景的请求在新场景上无意义。
static _Atomic(uint32_t) s_pending_op    = XRC_OP_NONE;
static _Atomic(uint32_t) s_pending_ms    = 0;
static _Atomic(uint64_t) s_pending_scene = 0;   // 登记请求时的 scene 指针
#define XRC_OP_MAX_IDLE_US  (4000 * 1000ULL)    // 请求超过 4s 未执行 → 丢弃

static uint64_t s_pending_created_us;

bool xrc_gameplay_request(xrc_op_t op, uint32_t param_ms) {
    if (![NSThread isMainThread] || op == XRC_OP_NONE || op > XRC_OP_LOOP_REWIND) return false;
    void *scene = atomic_load(&xrc_gp_instance);
    if (!scene) return false;
    uint32_t pending = atomic_load(&s_pending_op);
    // Automatic loop requests must not replace a user's most recent target.
    if (pending != XRC_OP_NONE && op == XRC_OP_LOOP_REWIND) return false;
    atomic_store(&s_pending_scene, (uint64_t)scene);
    atomic_store(&s_pending_ms, param_ms);
    s_pending_created_us = xrc_real_now_us();
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

// ---- retry 监视器 ----
// 场景：开启循环或 seek 定位后，游戏中暂停 → Retry（引擎重建场景）。
// 判据：**音频位置的帧间大回跳**——retry 重建场景会让音频
// 从曲尾/当前点回到曲首（jump < -10s），单点演奏不可能产生。
// 触发后写一个 pending seek（目标=capture）；deferred 状态机在**新场景**的下一帧
// 才执行（旧场景已被 retry 销毁，同一帧不可用）。执行后解除（一次性）。
// 阈值说明：retry/换歌重建后音频必然从曲中/曲尾回到 0ms 附近，单点演奏的
// 帧间正常波动不可能超过 10 秒 → -10s 是"重建类事件"的可靠判据。
#define XRC_RETRY_AUDIO_JUMP_MS  (-10000)   // 音频帧间回跳阈值
static _Atomic(bool)     s_cap_valid = false;   // 音频基准是否已建立
static int32_t           s_prev_audio_ms = -1;
// **自家 seek 标记**。帧内时序（见下）：s_exec_pending 下完 seek 后，音频位置要到下一帧
// 才真的落位（真机实测："pos 25045 -> 25045" 立即读是旧值）⇒ watcher 在下一帧必然看到
// 一次大回落。没有这个标记，循环开着时会把它当成外部 retry 再补一次 seek；有标记则
// 只消账、不动作。
static _Atomic(uint64_t) s_own_seek_us = 0;
#define XRC_OWN_SEEK_WIN_US  (3000 * 1000ULL)   // 自家 seek 的豁免窗：3s

// 帧内调用（note_group 有效时）：音频位置回跳检测。
static void s_retry_watch_tick(void) {
    // 监视常开（回位点由"循环是否开启"在触发时刻决定）。
    int32_t pos = (int32_t)xrc_player_position_ms();
    if (pos < 0) return;
    if (xrc_gameplay_seek_active()) return;
    if (!atomic_load(&s_cap_valid)) {
        s_prev_audio_ms = pos;
        atomic_store(&s_cap_valid, true);
        return;
    }
    int32_t jump = pos - s_prev_audio_ms;
    s_prev_audio_ms = pos;
    if (jump < XRC_RETRY_AUDIO_JUMP_MS) {
        // 先问「这一跳是不是我们自己 seek 出来的」——是则只消账，不动作。
        uint64_t own = atomic_load(&s_own_seek_us);
        if (own && xrc_real_now_us() - own < XRC_OWN_SEEK_WIN_US) {
            atomic_store(&s_own_seek_us, 0);
            xrc_logd(XRCLC_JUDGE, @"audio jump %d = 自家 seek（豁免，不外补）", jump);
            return;
        }
        // 手动 retry（或异常回跳）回位：**仅循环开启时**回 A 点。
        // 未开循环 = 不干预（不得锁到任何残留位置）。
        uint32_t a = 0, b = 0;
        xrc_loop_get_range(&a, &b);
        if (xrc_loop_get_enabled() && b > a + 1000) {
            if (xrc_gameplay_request(XRC_OP_LOOP_REWIND, a)) {
                xrc_logd(XRCLC_JUDGE, @"retry detected (audio jump %d) -> seek loop A %u", jump, a);
            }
        } else {
            xrc_logd(XRCLC_JUDGE, @"audio jump %d ignored (loop off)", jump);
        }
    }
}

// A seek owns one scene/player/clock until acknowledgement and replay completion.
// The audio channel keeps its existing paused state; never unpause a user's pause menu.
#define XRC_FRZ_OFF 0
#define XRC_FRZ_FROZEN 1
#define XRC_FRZ_RESYNC 2
#define XRC_FRZ_REBUILD 3
#define XRC_FRZ_MAX_US 1500000ULL
#define XRC_RESYNC_US 60000ULL
static _Atomic(int) s_frz_state;
static void *s_seek_scene, *s_seek_ng, *s_seek_player;
static uint32_t s_seek_audio_target;
static int32_t s_seek_offset, s_seek_previous;
static uint64_t s_seek_started_us, s_seek_deadline_us, s_seek_sequence;
static bool s_seek_force_replay;
static bool s_seek_has_freeze;
static uint64_t s_seek_result_sequence;
static bool s_seek_result_success;
// A completed seek must not turn its own transient error into new calibration.
static void *s_sync_scene, *s_sync_ng, *s_sync_player;
static int32_t s_sync_offset;
static bool s_sync_have_calibration;
static uint64_t s_sync_probe_until, s_sync_probe_last;

uint64_t xrc_gameplay_seek_result(bool *success) {
    if (success) *success = s_seek_result_success;
    return s_seek_result_sequence;
}

bool xrc_gameplay_seek_active(void) { return atomic_load(&s_frz_state) != XRC_FRZ_OFF; }

static void xrc_clock_shift_to(void *note_group, int32_t target) {
    if (!note_group) return;
    void *clk = *(void **)((char *)note_group + XRC_CLOCK_IN_NOTEGROUP_OFF);
    if (!clk) return;
    int32_t cur = xrc_chart_clock_ms(note_group);
    int32_t *base = (int32_t *)((char *)clk + XRC_CLK_BASE_OFF);
    int64_t value = (int64_t)*base + (int64_t)cur - target;
    *base = value > INT_MAX ? INT_MAX : value < INT_MIN ? INT_MIN : (int32_t)value;
}

static bool s_seek_context_valid(void *ng) {
    return atomic_load(&xrc_gp_instance) == s_seek_scene && ng == s_seek_ng &&
           xrc_player_get() == s_seek_player;
}

static void s_seek_finish(bool success) {
    if (!xrc_gameplay_seek_active()) return;
    uint32_t audio = 0;
    if (success && s_seek_context_valid(s_seek_ng) &&
        xrc_player_read_position(s_seek_player, &audio)) {
        xrc_clock_shift_to(s_seek_ng, xrc_seek_chart_target(audio, s_seek_offset));
        xrc_logi(XRCLC_JUDGE, @"[seek-sync] #%llu final audio=%u chart=%d delta=%lld",
                 s_seek_sequence, audio, xrc_chart_clock_ms(s_seek_ng),
                 (int64_t)xrc_chart_clock_ms(s_seek_ng) - audio);
    }
    s_seek_result_sequence = s_seek_sequence;
    s_seek_result_success = success;
    if (s_seek_has_freeze) {
        xrc_clock_freeze_dec();
        s_seek_has_freeze = false;
    }
    atomic_store(&s_frz_state, XRC_FRZ_OFF);
    s_sync_probe_until = xrc_real_now_us() + 2000000ULL;
    s_sync_probe_last = 0;
    s_gp_last_real_us = 0;
    s_retime_rem_us = 0;
    s_retime_acc = 0;
    s_prev_audio_ms = (int32_t)xrc_player_position_ms();
    atomic_store(&s_cap_valid, true);
    atomic_store(&s_own_seek_us, xrc_real_now_us());
    xrc_logi(XRCLC_JUDGE, @"[seek] #%llu %s target=%u offset=%d", s_seek_sequence,
             success ? "complete" : "failed/cancelled", s_seek_audio_target, s_seek_offset);
}

void xrc_freeze_end(void) {
    if (atomic_load(&s_frz_state) != XRC_FRZ_REBUILD) return;
    // Let the native clock leave its frozen epoch BEFORE reconciliation. Otherwise
    // the first resumed update adds rebuild elapsed time after our final alignment.
    if (s_seek_has_freeze) {
        xrc_clock_freeze_dec();
        s_seek_has_freeze = false;
    }
    s_gp_last_real_us = 0;
    s_retime_rem_us = 0;
    s_retime_acc = 0;
    s_seek_deadline_us = xrc_real_now_us() + XRC_RESYNC_US;
    atomic_store(&s_frz_state, XRC_FRZ_RESYNC);
}

static void s_frz_tick(void *ng) {
    int state = atomic_load(&s_frz_state);
    if (state == XRC_FRZ_OFF) return;
    if (!s_seek_context_valid(ng)) { s_seek_finish(false); return; }
    uint64_t now = xrc_real_now_us();
    uint32_t audio = 0;
    bool readable = xrc_player_read_position(s_seek_player, &audio);
    if (state == XRC_FRZ_FROZEN) {
        if (readable && xrc_seek_landed(audio, s_seek_audio_target,
                                        now - s_seek_started_us,
                                        xrc_audio_speed_enabled() ? xrc_clock_get_rate() : 1.0)) {
            int32_t chart = xrc_seek_chart_target(audio, s_seek_offset);
            xrc_clock_shift_to(ng, chart);
            atomic_store(&s_frz_state, XRC_FRZ_REBUILD);
            xrc_logi(XRCLC_JUDGE, @"[seek] #%llu landed audio=%u chart=%d offset=%d",
                     s_seek_sequence, audio, chart, s_seek_offset);
            if (chart < s_seek_previous)
                xrc_replay_seek((uint64_t)s_seek_scene, chart > 0 ? (uint32_t)chart : 0,
                                (uint32_t)s_seek_previous, s_seek_force_replay);
            xrc_freeze_end(); // Also closes no-replay/no-note paths.
        } else if (now >= s_seek_deadline_us) {
            // Never commit a failed target. Restore chart/audio relationship if readable.
            if (readable) xrc_clock_shift_to(ng, xrc_seek_chart_target(audio, s_seek_offset));
            s_seek_finish(false);
        } else {
            xrc_clock_shift_to(ng, s_seek_previous);
        }
    } else if (state == XRC_FRZ_RESYNC) {
        if (readable) xrc_clock_shift_to(ng, xrc_seek_chart_target(audio, s_seek_offset));
        if (now >= s_seek_deadline_us) s_seek_finish(readable);
    }
}

// Capture native calibration during ordinary playback, before a seek or rate change
// can contaminate a one-off measurement. DSP latency is not stored as calibration.
static void s_capture_sync_calibration(void *scene, void *ng) {
    if (xrc_gameplay_seek_active() || !ng) return;
    void *player = xrc_player_get();
    if (s_sync_have_calibration && s_sync_scene == scene && s_sync_ng == ng && s_sync_player == player) return;
    int32_t chart = xrc_chart_clock_ms(ng);
    uint32_t audio = 0;
    if (chart < 0 || !xrc_player_read_position(player, &audio)) return;
    double rate = xrc_audio_speed_enabled() ? xrc_clock_get_rate() : 1.0;
    int32_t delay = xrc_seek_output_delay(rate, xrc_audio_output_latency_ms());
    int64_t calibration = (int64_t)chart - audio + delay;
    if (calibration < INT_MIN || calibration > INT_MAX) return;
    s_sync_scene = scene; s_sync_ng = ng; s_sync_player = player;
    s_sync_offset = (int32_t)calibration; s_sync_have_calibration = true;
    xrc_logi(XRCLC_JUDGE, @"[seek-sync] native calibration=%d delay=%d rate=%.3f", s_sync_offset, delay, rate);
}

static void s_exec_pending(void *self) {
    if (xrc_gameplay_seek_active()) return;
    uint32_t op = atomic_load(&s_pending_op);
    if (op == XRC_OP_NONE) return;
    uint64_t now = xrc_real_now_us();
    if (atomic_load(&s_pending_scene) != (uint64_t)self ||
        now - s_pending_created_us > XRC_OP_MAX_IDLE_US) {
        atomic_store(&s_pending_op, XRC_OP_NONE);
        s_seek_result_sequence = ++s_seek_sequence;
        s_seek_result_success = false;
        xrc_logi(XRCLC_JUDGE, @"[seek] #%llu pending cancelled: expired or scene changed", s_seek_sequence);
        return;
    }
    void *ng = s_valid_note_group(self);
    void *player = xrc_player_get();
    uint32_t audio = 0;
    if (!ng || !player || !xrc_player_read_position(player, &audio)) return;
    int32_t chart = xrc_chart_clock_ms(ng);
    if (chart < 0) return; // Retain a request briefly while the same scene loads.
    uint32_t target = atomic_load(&s_pending_ms);
    uint32_t length = xrc_player_song_length_ms();
    if (length && target >= length) target = length - 1;
    if (target > INT_MAX) target = INT_MAX;
    int64_t measured = (int64_t)chart - audio;
    double rate = xrc_clock_get_rate();
    bool music = xrc_audio_speed_enabled();
    double audioRate = music ? rate : 1.0;
    double latency = xrc_audio_output_latency_ms();
    int32_t delay = xrc_seek_output_delay(audioRate, latency);
    if (!s_sync_have_calibration || s_sync_scene != self || s_sync_ng != ng || s_sync_player != player) {
        int64_t calibration = measured + delay;
        if (calibration < INT_MIN || calibration > INT_MAX) return;
        s_sync_scene = self; s_sync_ng = ng; s_sync_player = player;
        s_sync_offset = (int32_t)calibration;
        s_sync_have_calibration = true;
    }
    int64_t offset = xrc_seek_calibrated_offset(s_sync_offset, delay);
    xrc_logi(XRCLC_JUDGE, @"[seek-sync] measured=%lld calibration=%d outputDelay=%d baseline=%lld rate=%.3f music=%d",
             measured, s_sync_offset, delay, offset, rate, music);
    atomic_store(&s_pending_op, XRC_OP_NONE);
    if (offset < INT_MIN || offset > INT_MAX) return;
    s_seek_scene = self; s_seek_ng = ng; s_seek_player = player;
    s_seek_audio_target = target; s_seek_offset = (int32_t)offset;
    s_seek_previous = chart; s_seek_force_replay = op != XRC_OP_SEEK;
    s_seek_started_us = now; s_seek_deadline_us = now + XRC_FRZ_MAX_US;
    ++s_seek_sequence;
    xrc_clock_freeze_inc();
    s_seek_has_freeze = true;
    atomic_store(&s_frz_state, XRC_FRZ_FROZEN);
    // No chart write until the real channel acknowledges the new position.
    if (!xrc_player_seek_ms(player, target)) { s_seek_finish(false); return; }
    atomic_store(&s_own_seek_us, now);
    uint64_t sequence = s_seek_sequence;
    // GameScene.update may stop entirely on exit or pause. Do not leak our freeze.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((XRC_FRZ_MAX_US + XRC_RESYNC_US) * 1000ULL)),
                   dispatch_get_main_queue(), ^{
        if (xrc_gameplay_seek_active() && s_seek_sequence == sequence) s_seek_finish(false);
    });
    xrc_logi(XRCLC_JUDGE, @"[seek] #%llu requested=%u previous=%d offset=%d op=%u",
             s_seek_sequence, target, chart, s_seek_offset, op);
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
        // 这就是系统性漂移的来源。
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
// 变速有**两条独立通路** —— ① gettimeofday fishhook 把"游戏看到的
// 墙上时间"按 rate 缩放（管视觉/Cocos 逻辑），② gp.update 里对谱面钟 base_off 的
// 累积 retime（管音符时序）。若游戏自身的钟也走被 warp 的时间域，两者就会**叠加**，
// 谱面实际倍率变成 2·rate−1，而音频（FMOD 自有音频钟）仍是 rate —— 这就是
// "音画倍率不同步"。日志里把 设定值 / 谱面实际斜率 / 音频实际斜率 一起打出来，
// 直接看出是哪条路多算或少算。
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
        if (now < s_sync_probe_until)
            xrc_logi(XRCLC_BOOT, @"[rate] set=%.3f chart=%.3f audio=%.3f dt=%.2fs", rate, dchart / dt, dchan / dt, dt);
        else
            xrc_logd(XRCLC_BOOT, @"[rate] set=%.3f chart=%.3f audio=%.3f dt=%.2fs", rate, dchart / dt, dchan / dt, dt);
    }
    last_us = now; last_chart = chart; last_chan = chan; have = 1;
}

void xrc_gameplay_update(void *self, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5) {
    @try { if (!xrc_gameplay_seek_active()) xrc_audio_speed_tick(); } @catch (NSException *e) {}
    if (!self) {
        atomic_store(&xrc_gp_instance, NULL);
        s_frz_tick(NULL);
    }
    if (self) {
        atomic_store(&xrc_gp_instance, self);
        void *note_group = *(void **)((char *)self + XRC_GP_NOTEGROUP_OFF);
        if (xrc_gameplay_seek_active() && !s_seek_context_valid(note_group))
            s_seek_finish(false);
        if (note_group) {
            s_gp_retime_logic_clock(note_group);
            s_rate_probe_tick(note_group);      // 音画倍率自测（1 Hz，只读）
            int32_t pos = xrc_chart_clock_ms(note_group);
            // 冻结/收敛窗内钟不是真实播放时间（钉住/落位中）——循环 tick 抑制，
            // 防事务中间态二次触发回跳（收口缺守卫会把钟弹回旧位 → 循环二跳）。
            if (pos > 0 && !atomic_load(&s_frz_state)) xrc_loop_tick(self, xrc_player_position_ms());
        }
        s_exec_pending(self);   // deferred 操作（seek/循环回位）在活场景循环内执行

        // retry 监视（音频回跳）；循环卡死恢复。
        if (note_group) {
            s_retry_watch_tick();
            // 循环卡死恢复：pos 停滞超 1.5s 且位于 [A,B) 内 → 强制回 A
            int32_t pos = xrc_chart_clock_ms(note_group);
            static int32_t s_stall_pos = 0;
            static int32_t s_stall_audio_prev = -1;
            static uint64_t s_stall_audio_us = 0;    /* 音频最近一次变化的时间 */
            static uint64_t s_stall_since = 0;
            uint64_t now_us = xrc_real_now_us();
            {
                int32_t apos = (int32_t)xrc_player_position_ms();
                if (apos != s_stall_audio_prev) { s_stall_audio_prev = apos; s_stall_audio_us = now_us; }
            }
            if (atomic_load(&s_frz_state)) {
                // 冻结窗内钟是**故意钉住**的（停滞是预期行为）——监视豁免，
                // 防冻结满 1.5s 时误触发一次「卡死回绕」。
                s_stall_pos = pos;
                s_stall_since = now_us;
            } else if (pos != s_stall_pos) {
                s_stall_pos = pos;
                s_stall_since = now_us;
            } else if (now_us - s_stall_audio_us > 700000ULL) {
                // 钟静止但**音频 ≥0.7s 没动** ⇒ 暂停菜单/加载冻结，不是卡死——不计时。
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
    // 音乐变速：低频去重 tick —— 速度变了/换歌了/组刚建才动作。
    // 放这里是因为 gp.update 是唯一"进对局后每帧都在跑"的点，面板不开时也有效。
    @try { xrc_audio_speed_tick(); } @catch (NSException *e) {}
    if (s_orig_gp_update) s_orig_gp_update(self, a2, a3, a4, a5);
    // Native update refreshes clock fields. Reconcile afterwards so those writes
    // cannot undo the alignment in the same frame or add rebuild elapsed time.
    if (self && atomic_load(&xrc_gp_instance) == self) {
        void *ng = *(void **)((char *)self + XRC_GP_NOTEGROUP_OFF);
        s_capture_sync_calibration(self, ng);
        s_frz_tick(ng);
        uint64_t now = xrc_real_now_us();
        uint32_t audio = 0;
        if (!xrc_gameplay_seek_active() && now < s_sync_probe_until &&
            now - s_sync_probe_last >= 250000ULL && s_seek_context_valid(ng) &&
            xrc_player_read_position(s_seek_player, &audio)) {
            s_sync_probe_last = now;
            xrc_logi(XRCLC_JUDGE, @"[seek-sync] #%llu post audio=%u chart=%d delta=%lld baseline=%d",
                     s_seek_sequence, audio, xrc_chart_clock_ms(ng),
                     (int64_t)xrc_chart_clock_ms(ng) - audio, s_seek_offset);
        }
    }
}

void xrc_gameplay_install_hooks(uint64_t image_base) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!g_xrc.gp_vtable || !g_xrc.gp_update) {   // 锚点未就绪 → 降级（记日志）
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

// ---------------- 游戏主循环模式升级（面板滚动期间谱面不再冻结）----------------
// 机制：UIKit 在 UIScrollView 拖动期间把主 runloop 切到 UITrackingRunLoopMode，
// 注册在 default 模式的 CADisplayLink 停摆 ⇒ 整个游戏循环（谱面）冻结，而 FMOD
// 音频在独立线程继续播——两个体征合起来即"滑动面板：谱面停、音乐不停"。
// 做法：把 CADisplayLink 的 addToRunLoop:forMode: 一律升级注册到 common modes
//（含 tracking）——滚动期间游戏照常跑，音画一致；注册时打一行日志留痕。
static IMP s_orig_add_to_runloop = NULL;
static void s_cadl_add_common(id self_, SEL _cmd, NSRunLoop *rl, NSString *mode) {
    xrc_logi(XRCLC_BOOT, @"[boot] CADisplayLink addToRunLoop: %@ → common modes", mode);
    ((void (*)(id, SEL, NSRunLoop *, NSString *))s_orig_add_to_runloop)(self_, _cmd, rl,
                                                                        NSRunLoopCommonModes);
}

void xrc_gameplay_displaylink_common_install(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class c = NSClassFromString(@"CADisplayLink");
        SEL sel = NSSelectorFromString(@"addToRunLoop:forMode:");
        Method m = c ? class_getInstanceMethod(c, sel) : NULL;
        if (!m) { xrc_logw(XRCLC_BOOT, @"[boot] CADisplayLink hook miss"); return; }
        s_orig_add_to_runloop = method_getImplementation(m);
        method_setImplementation(m, (IMP)s_cadl_add_common);
    });
}


#pragma mark - 循环 / retry 回位（玩法语义说明）

/* ───────────────────────── 数据流总览 ─────────────────────────
 *
 * 循环区间 A/B：仅由面板「起点」/「终点」按钮写入；仅由面板「重置循环」
 *   按钮清除（xrc_loop_reset_all）。**没有任何自动清除路径**：retry 重建
 *   同样会重置曲长（len=143896->0），自动判据必然误伤。
 *
 * 循环开关：面板「循环 开/关」（区间完整才允许开启）。
 *
 * 到 B 点（循环开）：deferred seek 平移回 A（练习定位语义：已判音符不
 *   重现、计分不回滚；不触碰游戏状态机，无卡死风险）。
 *
 * 手动 Retry（游戏原生重建，安全）：重建后音频回跳（>-10s）被检测 →
 *   **仅当循环开启**时 seek 回 A；未开循环则不干预。
 *
 * 程序化 retry：不可用（重触发会污染 GameModel action 队列致卡死），
 *   本插件不做；路径记录见 XRCProfile.h 的 retry 触发链注释段。
 * ──────────────────────────────────────────────────────────────── */

/*
 * 玩法定义：
 *
 * 【A-B 循环练习】
 *   用户流程：播放到起点按「起点」→ 播放到终点按「终点」→ 开「循环」。
 *   到 B 点 → deferred seek 平移回 A（音频 seek + 谱面钟 base 平移）。
 *   语义：练习定位——已判音符不重现、计分不回滚（不触碰游戏状态机、
 *   无卡死风险）。
 *
 * 【完整重打（音符重现）】
 *   用户暂停菜单自行 Retry（游戏原生重建链，安全），重建后音频回跳检测
 *   随即把进度拉回 A（retry detected -> seek A）。
 *
 * 【程序化 retry（禁止调用）】
 *   触发调用被游戏静默忽略（Retry 回调首校验 PauseLayer+0x298==1），
 *   重复尝试还会污染 GameModel action 队列致手动 retry 卡在转场界面。
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
    // 设定区间**不自动启用**（面板流程：设起点→设终点→开循环）。
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
// 换歌/退出重进 = 练习状态归零（只要退出重进就视作换歌，哪怕同一首）。
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

