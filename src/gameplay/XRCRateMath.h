#pragma once
#include <math.h>
#include <stdint.h>
#include <stdbool.h>
#include <limits.h>

static inline double xrc_adapt_rate(double rate) {
    return isfinite(rate) && rate >= 0.01 && rate <= 4.0 ? rate : 1.0;
}
static inline double xrc_adapt_flow_factor(double rate, bool enabled) {
    return enabled ? xrc_adapt_rate(rate) : 1.0;
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
// Native highspeed_int stores speed in tenths, so the field limit is INT32_MAX.
static inline bool xrc_live_flow_units(double speed, uint64_t *units) {
    if (!units || !isfinite(speed) || speed < 0.1 || speed > (double)INT32_MAX / 10.0) return false;
    *units = (uint64_t)floor(speed * 10.0 + 0.5);
    return *units >= 1 && *units <= (uint64_t)INT32_MAX;
}
// Round the actual native highspeed_int value; never scale render intermediates.
static inline int32_t xrc_flow_value(int32_t base,double rate,bool adapt) {
    if (base<=0) return 0;
    double result=adapt ? base*xrc_adapt_rate(rate) : base;
    if (result>=INT_MAX) return INT_MAX;
    return result<1 ? 1 : (int32_t)floor(result+0.5);
}

static inline int32_t xrc_flow_write_value(int32_t plugin,int32_t native) {
    return plugin>0 ? plugin : native;
}
