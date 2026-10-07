#pragma once
#include <stdbool.h>
#include <stdint.h>

// Panel IDs follow the requested five choices; native tap gauge is challenge 5.
static inline bool xrc_konzetsu_valid_id(int id) {
    return id == 1 || id == 2 || id == 3 || id == 4 || id == 6;
}
static inline int xrc_konzetsu_native_id(int id) {
    return id == 4 ? 5 : (xrc_konzetsu_valid_id(id) ? id : 0);
}
static inline uint32_t xrc_konzetsu_options(int id, bool effects, bool gauge) {
    return (uint32_t)(xrc_konzetsu_valid_id(id) ? id : 1)
        | (effects ? 0x100u : 0) | (gauge ? 0x200u : 0);
}
static inline bool xrc_konzetsu_effects(uint32_t options) {
    return (options & 0x100u) != 0;
}
static inline bool xrc_konzetsu_gauge(uint32_t options) {
    return xrc_konzetsu_effects(options) && (options & 0x200u) != 0;
}
static inline int32_t xrc_konzetsu_scaled_time(int32_t ms, uint32_t duration) {
    // General charts use the Arghena pattern scaled to the chart's note span.
    if (duration < 1000 || duration > 1200000) return 0;
    return (int32_t)((int64_t)ms * duration / 150300);
}

typedef struct { int32_t begin, end; } xrc_konzetsu_interval_t;
static inline bool xrc_konzetsu_scale_interval(xrc_konzetsu_interval_t source,
                                              uint32_t duration,
                                              xrc_konzetsu_interval_t *out) {
    if (!out || source.begin < 0 || source.end <= source.begin ||
        source.end > 150300 || duration < 1000 || duration > 1200000) return false;
    out->begin = xrc_konzetsu_scaled_time(source.begin, duration);
    out->end = xrc_konzetsu_scaled_time(source.end, duration);
    return out->end > out->begin && (uint32_t)out->end <= duration;
}
