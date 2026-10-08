#pragma once
#include <math.h>
#include <stdint.h>
#include <stdbool.h>
#include <limits.h>

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
    return isfinite(left) && isfinite(right) && fabsf(left - right) <= 0.00001f * fmaxf(1.0f, fabsf(right));
}
// Integer-only version for the SIGTRAP handler: no libm calls or allocation.
static inline int32_t xrc_adapt_window_units(int32_t original, uint32_t rate) {
    int64_t result = ((int64_t)original * rate + 500) / 1000;
    return result > INT_MAX ? INT_MAX : result < 1 ? 1 : (int32_t)result;
}
