#pragma once
#include <math.h>
#include <stdint.h>
#include <stdbool.h>
#include <limits.h>
#include <float.h>

static inline double xrc_adapt_rate(double rate) {
    return isfinite(rate) && rate >= 0.01 && rate <= 4.0 ? rate : 1.0;
}
static inline double xrc_adapt_flow_factor(double rate, bool enabled) {
    return enabled ? 1.0 / xrc_adapt_rate(rate) : 1.0;
}
// Native chart time subtracts the user's offset. To retain O real milliseconds
// at rate r, the internal offset is r*O; the extra clock base is (r-1)*O.
static inline int32_t xrc_adapt_offset_extra(int32_t offset, double rate, bool enabled) {
    double extra = enabled ? (xrc_adapt_rate(rate) - 1.0) * offset : 0.0;
    if (extra >= INT_MAX) return INT_MAX;
    if (extra <= INT_MIN) return INT_MIN;
    return (int32_t)llround(extra);
}
static inline int32_t xrc_adapt_add(int32_t value, int64_t delta) {
    int64_t result = (int64_t)value + delta;
    return result > INT_MAX ? INT_MAX : result < INT_MIN ? INT_MIN : (int32_t)result;
}
static inline int32_t xrc_adapt_window(int32_t original, double rate) {
    double result = (double)original * xrc_adapt_rate(rate);
    if (result >= INT_MAX) return INT_MAX;
    return result < 1.0 ? 1 : (int32_t)llround(result);
}
static inline bool xrc_adapt_same_scale(float left, float right) {
    return isfinite(left) && isfinite(right) && fabsf(left - right) <=
        0.00001f * fmaxf(FLT_MIN, fmaxf(fabsf(left), fabsf(right)));
}
// Manual speed is stored in 64-bit tenths, never in native int32 highspeed_int.
static inline bool xrc_live_flow_units(double speed, uint64_t *units) {
    if (!units || !isfinite(speed) || speed < 0.1 || speed > INT32_MAX) return false;
    *units = (uint64_t)floor(speed * 10.0 + 0.5);
    return *units >= 1 && *units <= (uint64_t)INT32_MAX * 10;
}
static inline double xrc_live_flow_factor(double base, double requested, double rate, bool adapt) {
    if (!isfinite(base) || base <= 0) return 1.0;
    return (requested > 0 ? requested / base : 1.0) * xrc_adapt_flow_factor(rate, adapt);
}
#define XRC_FLOW_WINDOW_DENOM 1000000ULL
static inline uint64_t xrc_live_window_factor(double scale) {
    double factor = XRC_FLOW_WINDOW_DENOM / scale;
    return !isfinite(factor) || factor >= UINT64_MAX ? UINT64_MAX :
        factor < 0.5 ? 0 : (uint64_t)floor(factor + 0.5);
}
// Integer-only, saturating multiplication for the signal handler.
static inline int32_t xrc_live_window(int32_t original, uint64_t factor) {
    if (original <= 0 || !factor) return 1;
    uint64_t limit = (uint64_t)INT32_MAX * XRC_FLOW_WINDOW_DENOM;
    if (factor > (limit - XRC_FLOW_WINDOW_DENOM / 2) / (uint32_t)original) return INT32_MAX;
    uint64_t result = ((uint64_t)(uint32_t)original * factor + XRC_FLOW_WINDOW_DENOM / 2) / XRC_FLOW_WINDOW_DENOM;
    return result < 1 ? 1 : (int32_t)result;
}
// Integer-only version for the SIGTRAP handler: no libm calls or allocation.
static inline int32_t xrc_adapt_window_units(int32_t original, uint32_t rate) {
    int64_t result = ((int64_t)original * rate + 500) / 1000;
    return result > INT_MAX ? INT_MAX : result < 1 ? 1 : (int32_t)result;
}
