// © 雾月星辰 & MLXC · github@XingChenRS
// XRCAudio.m — 音乐变速实现。设计与依据见 XRCAudio.h 顶部。
//
// 调用纪律：所有 FMOD 调用都先判空（入口未解析 / system 未就绪 / 播放器未创建都可能发生），
// 失败记日志；算法创建失败时退化为变速但不保音高。
#import "XRCAudio.h"
#include "XRCLog.h"
#include "XRCProfile.h"
#include "XRCClock.h"
#include "XRCSeekMath.h"
#include "XRCAudioStretch.h"
#include "XRCPlayer.h"
#include "XRCGameplay.h"

#include <stdatomic.h>
#include <stdint.h>
#include <string.h>

extern uint64_t xrc_image_base(void);

// ---------------- FMOD 入口（偏移见 XRCProfile.h） ----------------
typedef int32_t (*fmod_cc_set_pitch_t)(void *, float);
typedef int32_t (*fmod_cc_add_dsp_t)(void *, int32_t, void *);
typedef int32_t (*fmod_cc_remove_dsp_t)(void *, void *);
typedef int32_t (*fmod_dsp_release_t)(void *);
typedef int32_t (*fmod_ch_getpos_t)(void *, uint32_t *, uint32_t);
typedef int32_t (*fmod_ch_setpos_t)(void *, uint32_t, uint32_t);
static fmod_cc_set_pitch_t p_set_pitch;
static fmod_cc_add_dsp_t p_add_dsp;
static fmod_cc_remove_dsp_t p_remove_dsp;
static fmod_dsp_release_t p_dsp_release;
static fmod_ch_getpos_t    p_ch_getpos;
static fmod_ch_setpos_t    p_ch_setpos;

static void s_resolve(void) {
    static atomic_int done;
    if (atomic_exchange(&done, 1)) return;
    uint64_t mb = xrc_image_base();
    if (!mb) return;
    p_set_pitch   = (fmod_cc_set_pitch_t)(mb + XRC_OFF_FMOD_CC_SET_PITCH);
    p_add_dsp     = (fmod_cc_add_dsp_t)  (mb + XRC_OFF_FMOD_CC_ADD_DSP);
    p_remove_dsp = (fmod_cc_remove_dsp_t)(mb + XRC_OFF_FMOD_CC_REMOVE_DSP);
    p_dsp_release = (fmod_dsp_release_t) (mb + XRC_OFF_FMOD_DSP_RELEASE);
    p_ch_getpos   = (fmod_ch_getpos_t)   (mb + XRC_OFF_CH_GET_POSITION);
    p_ch_setpos   = (fmod_ch_setpos_t)   (mb + XRC_OFF_CH_SET_POSITION);
}

static BOOL s_ptr_ok(void *p) {
    uintptr_t v = (uintptr_t)p;
    return v > 0x100000000ULL && v < 0x800000000000ULL;
}

static uint64_t s_system(void) {
    uint64_t mb = xrc_image_base();
    if (!mb) return 0;
    uint64_t v = *(volatile uint64_t *)(uintptr_t)(mb + XRC_OFF_FMOD_SYSTEM_GLOBAL);
    return s_ptr_ok((void *)v) ? v : 0;
}

static void *s_bgm_group(void) {
    void *player = xrc_player_get();
    if (!player) return NULL;
    void *g = *(void **)((char *)player + XRC_PLAYER_BGM_GROUP_OFF);
    return s_ptr_ok(g) ? g : NULL;
}

static void *s_channel0(void) {
    void *player = xrc_player_get();
    if (!player) return NULL;
    char *tbl = *(char **)((char *)player + XRC_PLAYER_CHANNELS_OFF);
    if (!tbl) return NULL;
    void *c = *(void **)(tbl + XRC_CHANNEL_ENTRY_PTR_OFF);
    return s_ptr_ok(c) ? c : NULL;
}

// ---------------- 状态 ----------------
static void *s_dsp;
static void *s_dsp_group;          // DSP 当前挂在哪个组（换歌会换组）
static double s_dsp_lat_ms;        // 算法报告的输入 + 输出延迟，使用实际混音采样率
static double s_applied_rate = 1.0;
static void *s_applied_group;
static uint64_t s_owned_seek_until;
static uint32_t s_last_pos_ms;     // 位置回退检测（seek/retry 后要重新补偿）
static atomic_bool s_enabled = true;
static atomic_int s_alignment_adjustment;

void xrc_audio_speed_set_enabled(BOOL on) {
    bool prev = atomic_exchange(&s_enabled, (bool)on);
    if (prev && !on) xrc_audio_speed_apply(1.0);   // 保留固定延迟，避免开关时音频位置跳变
}
BOOL xrc_audio_speed_enabled(void) { return atomic_load(&s_enabled) ? YES : NO; }

static void s_release_dsp(void) {
    if (!s_dsp) return;
    int32_t removed=p_remove_dsp && s_dsp_group ? p_remove_dsp(s_dsp_group,s_dsp) : 0;
    int32_t released=p_dsp_release ? p_dsp_release(s_dsp) : -1;
    if (released!=0) xrc_logw(XRCLC_BOOT,@"[audio] stretch release=%d remove=%d",released,removed);
    s_dsp=NULL; s_dsp_group=NULL; s_dsp_lat_ms=0;
}

// 延迟补偿：把通道位置前移 rate·L（一次性；此后"内容位置"与"听到的声音"恒差 L）。
// 只在挂载/位置回退时做 —— 每次改速度都补会叠加偏移。
static void s_compensate(void *ch, double rate) {
    if (!ch || s_dsp_lat_ms <= 0.05f || !p_ch_getpos || !p_ch_setpos) return;
    uint32_t pos = 0;
    if (p_ch_getpos(ch, &pos, 1 /*FMOD_TIMEUNIT_MS*/) != 0) return;   // 拿不到就放弃补偿
    uint32_t bump = (uint32_t)(rate * (double)s_dsp_lat_ms + 0.5);
    if (bump && p_ch_setpos(ch,pos+bump,1)==0) {
        xrc_stretch_reset();
        atomic_store(&s_alignment_adjustment,0);
    }
}

void xrc_audio_speed_apply(double rate) {
    if (xrc_gameplay_seek_active()) return;
    s_resolve();
    if (!p_set_pitch) return;
    if (!atomic_load(&s_enabled) || !isfinite(rate)) rate=1.0;
    rate=fmax(0.05,fmin(4.0,rate));
    void *group=s_bgm_group();
    if (!group) return;
    if (group!=s_applied_group) atomic_store(&s_alignment_adjustment,0);
    if (s_dsp_group && s_dsp_group!=group) s_release_dsp();
    bool attached=false;
    if (!s_dsp && rate!=1.0) {
        uint64_t system=s_system();
        int32_t rc=system ? xrc_stretch_create(system,&s_dsp) : -1;
        if (rc==0 && s_ptr_ok(s_dsp)) rc=p_add_dsp ? p_add_dsp(group,0,s_dsp) : -1;
        if (rc==0 && s_ptr_ok(s_dsp)) {
            s_dsp_group=group; s_dsp_lat_ms=xrc_stretch_latency_ms();
            xrc_stretch_reset(); attached=true;
            xrc_logi(XRCLC_BOOT,@"[audio] Signalsmith Stretch ready latency=%.2fms",s_dsp_lat_ms);
        } else {
            s_release_dsp();
            xrc_logw(XRCLC_BOOT,@"[audio] stretch unavailable rc=%d; speed only",rc);
        }
    }
    xrc_stretch_set_rate(rate);
    int32_t rc=p_set_pitch(group,(float)rate);
    if (rc!=0) {
        xrc_stretch_set_rate(s_applied_rate);
        xrc_logw(XRCLC_BOOT,@"[audio] setPitch failed rc=%d",rc);
        return;
    }
    if (!attached && s_dsp && s_applied_group==group) {
        // Keep the source continuous; move the chart by the change in DSP delay.
        int32_t delta=xrc_seek_output_delay(rate,s_dsp_lat_ms)-
                      xrc_seek_output_delay(s_applied_rate,s_dsp_lat_ms);
        atomic_fetch_add(&s_alignment_adjustment,delta);
    }
    s_applied_rate=rate; s_applied_group=group;
    if (attached) s_compensate(s_channel0(),rate);
    void *channel=s_channel0(); uint32_t position=0;
    if (channel && p_ch_getpos && p_ch_getpos(channel,&position,1)==0) s_last_pos_ms=position;
}

void xrc_audio_speed_tick(void) {
    if (xrc_gameplay_seek_active()) return;
    s_resolve();
    if (!p_set_pitch) return;
    void *group = s_bgm_group();
    double rate = atomic_load(&s_enabled) ? xrc_clock_get_rate() : 1.0;

    // seek/retry 检测：位置回退 ⇒ 重新做一次延迟补偿（补偿是一次性偏移，会被 seek 冲掉）
    if (s_dsp && s_dsp_group==group && s_dsp_lat_ms > 0.05f) {
        void *ch = s_channel0();
        uint32_t pos = 0;
        if (ch && p_ch_getpos && p_ch_getpos(ch, &pos, 1) == 0) {
            if (xrc_seek_audio_needs_compensation(pos,s_last_pos_ms,xrc_real_now_us(),s_owned_seek_until,false)) { xrc_stretch_reset(); s_compensate(ch,rate); }
            s_last_pos_ms = pos;
        }
    }
    if (rate == s_applied_rate && group == s_applied_group) return;   // 去重：每帧只做一次比较
    xrc_audio_speed_apply(rate);
}

NSString *xrc_audio_speed_status(void) {
    void *group = s_bgm_group();
    return [NSString stringWithFormat:@"音乐变速：%s ｜ rate %.2f ｜ 高质量拉伸 %@",
            group ? "就绪" : "待进对局",s_applied_rate,
            s_dsp && s_dsp_group==group ? [NSString stringWithFormat:@"✓（延迟 %.0fms）",s_dsp_lat_ms] : @"未挂载"];
}

double xrc_audio_output_latency_ms(void) {
    void *group = s_bgm_group();
    return s_dsp && group && s_dsp_group == group ? (double)s_dsp_lat_ms : 0.0;
}

double xrc_audio_effective_rate(void) { return s_applied_rate; }
int32_t xrc_audio_take_alignment_adjustment(void) { return atomic_exchange(&s_alignment_adjustment,0); }
void xrc_audio_alignment_acknowledged(void) { atomic_store(&s_alignment_adjustment,0); }
void xrc_audio_seek_finished(void) {
    xrc_stretch_reset();
    s_owned_seek_until=xrc_real_now_us()+2000000ULL;
    void *channel=s_channel0(); uint32_t position=0;
    if (channel && p_ch_getpos && p_ch_getpos(channel,&position,1)==0) s_last_pos_ms=position;
}
