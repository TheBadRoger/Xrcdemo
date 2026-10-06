#include "XRCFlow.h"
#include "XRCPracticeMath.h"
#include "XRCProfile.h"
#include "XRCHook.h"
#include "XRCConfig.h"
#include <stdatomic.h>
#include <string.h>

extern uint64_t xrc_image_base(void);
static _Atomic(int32_t) s_requested = 0;
static uint64_t s_applied_settings;
static int32_t s_applied_units;

static uint64_t s_settings(void) {
    uint64_t base = xrc_image_base();
    if (!base) return 0;
    uint64_t app = *(const uint64_t *)(base + XRC_OFF_APP_GLOBAL);
    return app ? *(const uint64_t *)(app + 112) : 0;
}

bool xrc_flow_set(double speed) {
    int32_t units;
    if (!xrc_practice_flow_units(speed, &units)) return false;
    atomic_store(&s_requested, units);
    s_applied_settings = 0;
    xrc_flow_tick();
    return true;
}

double xrc_flow_get(void) {
    uint64_t settings = s_settings();
    if (settings) return (double)*(const int32_t *)(settings + 12) / 10.0;
    return (double)atomic_load(&s_requested) / 10.0;
}

void xrc_flow_tick(void) {
    int32_t units = atomic_load(&s_requested);
    if (!units || !xrc_feature_complete("note_flow")) return;
    uint64_t settings = s_settings();
    if (!settings) return;
    if (settings == s_applied_settings && units == s_applied_units) {
        int32_t current = *(const int32_t *)(settings + 12);
        if (current > 0 && current != units) {
            atomic_store(&s_requested, current);
            s_applied_units = current;
            xrc_config_t config;
            xrc_config_load(&config);
            config.note_flow = (double)current / 10.0;
            xrc_config_save(&config);
        }
        return;
    }
    uint64_t setter = xrc_image_base() + XRC_OFF_FLOW_SETTER;
    const unsigned char expected[4] = {0xf4, 0x4f, 0xbe, 0xa9};
    if (memcmp((const void *)setter, expected, sizeof(expected))) return;
    ((void (*)(uint64_t, int32_t))setter)(settings, units);
    s_applied_settings = settings;
    s_applied_units = units;
}
