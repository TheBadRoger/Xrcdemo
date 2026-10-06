#pragma once
#include <math.h>
#include <stdint.h>
#include <limits.h>
#include <stdbool.h>

static inline double xrc_practice_rate(double rate) {
    return isfinite(rate) && rate > 0.0 ? rate : 1.0;
}

static inline int32_t xrc_practice_bound(int32_t anchor, double offset) {
    double value = (double)anchor + offset;
    if (value >= INT32_MAX) return INT32_MAX;
    if (value <= INT32_MIN) return INT32_MIN;
    return (int32_t)value;
}

static inline int xrc_practice_grade(int32_t delta, const int th[4], double rate, bool locked) {
    double error = locked ? (double)delta / xrc_practice_rate(rate) : (double)delta;
    if (error < th[0]) return 0;
    if (error < th[1]) return 1;
    if (error < th[2]) return 2;
    if (error <= th[3]) return 3;
    return -1;
}

static inline bool xrc_practice_flow_units(double speed, int32_t *units) {
    if (!isfinite(speed) || speed < 0.1 || speed > (double)INT32_MAX / 10.0) return false;
    double rounded = floor(speed * 10.0 + 0.5);
    if (rounded < 1 || rounded > INT32_MAX) return false;
    *units = (int32_t)rounded;
    return true;
}
