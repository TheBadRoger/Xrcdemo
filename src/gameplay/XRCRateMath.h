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
// Native highspeed_int stores speed in tenths, so the field limit is INT32_MAX.
static inline bool xrc_live_flow_units(double speed, uint64_t *units) {
    if (!units || !isfinite(speed) || speed < 0.1 || speed > (double)INT32_MAX / 10.0) return false;
    *units = (uint64_t)floor(speed * 10.0 + 0.5);
    return *units >= 1 && *units <= (uint64_t)INT32_MAX;
}
static inline double xrc_live_flow_factor(double base, double requested, double rate, bool adapt) {
    if (!isfinite(base) || base <= 0) return 1.0;
    return (requested > 0 ? requested / base : 1.0) * xrc_adapt_flow_factor(rate, adapt);
}
// Scale native relative distances before FCVTZS, preserving its finite int32 range.
static inline float xrc_native_flow_distance(float value, double factor) {
    double result=(double)value*factor;
    if (!isfinite(result)) return result<0 ? -2147483648.0f : 2147483520.0f;
    if (result>2147483520.0) return 2147483520.0f;
    if (result<-2147483648.0) return -2147483648.0f;
    return (float)result;
}
// Two endpoints and six absolute mesh vertices (native build copies their Z).
static inline void xrc_arc_flow_geometry(float out[24],const float original[24],
                                         const float current[24],double factor,bool clipped) {
    for (unsigned i=0;i<24;++i) {
        unsigned record=i/3;
        bool head=record==0 || (record>=2 && record<=4);
        out[i]=clipped && head ? current[i] :
            i%3==2 ? xrc_native_flow_distance(original[i],factor) : original[i];
    }
}
// Widen only candidate lookup for slow flow; native visible thresholds stay intact.
static inline float xrc_native_flow_candidate(float index, float window, double factor,
                                             bool upper, int32_t minimum, int32_t maximum) {
    if (factor>=1 || factor<=0) return index;
    double delta=((double)window/factor-window)/10000.0;
    double result=(double)index+(upper ? delta : -delta);
    if (result<minimum) return (float)minimum;
    if (result>maximum) return (float)maximum;
    return (float)result;
}
