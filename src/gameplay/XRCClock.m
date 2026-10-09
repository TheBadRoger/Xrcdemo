// © 雾月星辰 & MLXC · github@XingChenRS
// XRCClock.m — 时间基准：真实时间单一实现 + warp 计算 + freeze。

#import <Foundation/Foundation.h>
#import "XRCLog.h"          // 拒绝非法 rate 时留痕
#include "XRCClock.h"
#include "XRCClockMath.h"
#include "XRCRateAdapt.h"

static _Atomic(uint64_t) s_t0_real_us = 0;
static _Atomic(uint64_t) s_t0_warp_us = 0;
static _Atomic(uint32_t) s_rate_x1000  = 1000;
static _Atomic(int32_t)  s_freeze_count = 0;
static _Atomic(uint64_t) s_frozen_us    = 0;

int (*xrc_clock_orig_gettimeofday)(struct timeval *, void *) = NULL;

uint64_t xrc_real_now_us(void) {
    struct timeval tv = {0};
    if (xrc_clock_orig_gettimeofday && xrc_clock_orig_gettimeofday(&tv, NULL) == 0)
        return (uint64_t)tv.tv_sec * 1000000ULL + (uint64_t)tv.tv_usec;
    if (gettimeofday(&tv, NULL) == 0)
        return (uint64_t)tv.tv_sec * 1000000ULL + (uint64_t)tv.tv_usec;
    return 0;
}

double xrc_clock_get_rate(void) {
    return (double)atomic_load(&s_rate_x1000) / 1000.0;
}

static uint64_t s_compute_warp_us(uint64_t real_us) {
    double rate = xrc_clock_get_rate();
    uint64_t t0r = atomic_load(&s_t0_real_us);
    uint64_t t0w = atomic_load(&s_t0_warp_us);
    return xrc_clock_warp_value(real_us,t0r,t0w,rate);
}

void xrc_clock_warp_reset(void) {
    uint64_t real_now = xrc_real_now_us();
    uint64_t warp_now = s_compute_warp_us(real_now);
    atomic_store(&s_t0_real_us, real_now);
    atomic_store(&s_t0_warp_us, warp_now);
}

void xrc_clock_set_rate(double rate) {
    if (rate <= 0.001) { xrc_logd(XRCLC_BOOT, @"clock rate rejected: %.4f", rate); return; }
    xrc_clock_warp_reset();
    atomic_store(&s_rate_x1000, (uint32_t)(rate * 1000.0 + 0.5));
    if ([NSThread isMainThread]) xrc_rate_adapt_native_tick();
}

void xrc_clock_freeze_inc(void) {
    int32_t prev = atomic_fetch_add(&s_freeze_count, 1);
    if (prev == 0)
        atomic_store(&s_frozen_us, s_compute_warp_us(xrc_real_now_us()));
}

void xrc_clock_freeze_dec(void) {
    int32_t prev = atomic_fetch_sub(&s_freeze_count, 1);
    if (prev <= 0) {
        atomic_store(&s_freeze_count, 0);
        return;
    }
    if (prev == 1) {
        uint64_t real_now = xrc_real_now_us();
        uint64_t frozen = atomic_load(&s_frozen_us);
        atomic_store(&s_t0_real_us, real_now);
        atomic_store(&s_t0_warp_us, frozen ? frozen : real_now);
    }
}

int32_t xrc_clock_freeze_count(void) {
    return atomic_load(&s_freeze_count);
}

int xrc_clock_gettimeofday(struct timeval *tv, void *tz) {
    if (!tv) return xrc_clock_orig_gettimeofday ? xrc_clock_orig_gettimeofday(tv, tz) : gettimeofday(tv, tz);
    int r = xrc_clock_orig_gettimeofday ? xrc_clock_orig_gettimeofday(tv, tz) : gettimeofday(tv, tz);
    if (r != 0) return r;
    uint64_t real_us = (uint64_t)tv->tv_sec * 1000000ULL + (uint64_t)tv->tv_usec;
    uint64_t warp_us;
    if (atomic_load(&s_freeze_count) > 0) {
        uint64_t f = atomic_load(&s_frozen_us);
        warp_us = f ? f : real_us;
    } else {
        warp_us = s_compute_warp_us(real_us);
    }
    if (warp_us == real_us) return r;
    tv->tv_sec  = (time_t)(warp_us / 1000000ULL);
    tv->tv_usec = (suseconds_t)(warp_us % 1000000ULL);
    return r;
}
