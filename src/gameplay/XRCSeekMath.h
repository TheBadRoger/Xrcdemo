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

// Convert real output latency to audio/chart milliseconds at the current playback rate.
static inline int32_t xrc_seek_output_delay(double rate, double latency_ms) {
    if (!(rate > 0.0) || !(latency_ms > 0.0) || rate > 4.0 || latency_ms > 5000.0) return 0;
    return (int32_t)(rate * latency_ms + 0.5);
}
static inline int32_t xrc_seek_calibrated_offset(int32_t calibration, int32_t delay) {
    int64_t value = (int64_t)calibration - delay;
    return value > INT_MAX ? INT_MAX : value < INT_MIN ? INT_MIN : (int32_t)value;
}
