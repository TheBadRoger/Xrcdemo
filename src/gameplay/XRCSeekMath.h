#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <limits.h>

// Targets originate in the audio timeline. Preserve chart - audio, including calibration.
static inline int32_t xrc_seek_chart_target(uint32_t audio, int32_t offset) {
    int64_t value = (int64_t)audio + offset;
    return value > INT_MAX ? INT_MAX : value < INT_MIN ? INT_MIN : (int32_t)value;
}
static inline bool xrc_seek_landed(uint32_t audio, uint32_t target,
                                   uint64_t elapsed_us, double rate) {
    // A playing channel advances while the asynchronous seek is being acknowledged.
    int64_t delta = (int64_t)audio - target;
    double advance = (double)elapsed_us / 1000.0 * rate;
    return delta >= -150 && (double)delta <= advance + 150.0;
}
