#pragma once
#include <stdint.h>
// Keep the accumulated epoch even on a return to 1x.
static inline uint64_t xrc_clock_warp_value(uint64_t real,uint64_t origin,
                                           uint64_t warped,double rate) {
    if (!origin) return real;
    if (real<=origin) return warped;
    return warped+(uint64_t)((double)(real-origin)*rate);
}
