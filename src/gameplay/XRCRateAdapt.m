#define _XOPEN_SOURCE 700
#include <ucontext.h>
#undef _XOPEN_SOURCE
#include <mach/arm/thread_status.h>
#include <mach/mach.h>
#include <stdatomic.h>
#include <string.h>
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif
#import <Foundation/Foundation.h>
#include "XRCRateAdapt.h"
#include "XRCRateMath.h"
#include "XRCClock.h"
#include "XRCGameplay.h"
#include "XRCProfile.h"
#include "XRCHook.h"
#import "XRCLog.h"

extern uint64_t xrc_image_base(void);
static _Atomic(bool) s_offset_enabled, s_flow_enabled;
static _Atomic(uint64_t) s_window_ng;
static _Atomic(uint32_t) s_window_rate = 1000;
static uint64_t s_scene, s_ng, s_clock, s_song;
static int32_t s_original_offset, s_extra;
static uint64_t s_node;
static float s_base_z = 1.0f, s_last_z = 1.0f;
static bool s_scaled, s_setter_valid;
static void (*s_set_scale_z)(void *, float);

static bool s_read(uint64_t address, void *out, size_t size) {
    vm_size_t read = 0;
    return address && vm_read_overwrite(mach_task_self(), address, size,
        (vm_address_t)out, &read) == KERN_SUCCESS && read == size;
}
static uint64_t s_u64(uint64_t address) {
    uint64_t value = 0; s_read(address, &value, sizeof(value)); return value;
}
static int32_t s_preference_offset(void) {
    uint64_t app = s_u64(xrc_image_base() + XRC_OFF_APP_GLOBAL);
    uint64_t preferences = app ? s_u64(app + 112) : 0;
    int32_t fields[3] = {0};
    if (!preferences || !s_read(preferences, fields, sizeof(fields))) return 0;
    // UserPreferences audio preset selects the ordinary or Bluetooth offset.
    return fields[fields[0] ? 2 : 1];
}
void xrc_rate_adapt_install(void) {
    uint64_t function = xrc_image_base() + XRC_OFF_NODE_SCALE_Z;
    static const unsigned char fingerprint[16] = {
        0x01,0x34,0x40,0xbd,0x20,0x20,0x20,0x1e,
        0x41,0x00,0x00,0x54,0xc0,0x03,0x5f,0xd6
    };
    unsigned char actual[16];
    s_setter_valid = s_read(function, actual, sizeof(actual))
        && !memcmp(actual, fingerprint, sizeof(actual));
    if (s_setter_valid) {
        void *pointer = (void *)function;
#if __has_feature(ptrauth_calls)
        pointer = ptrauth_sign_unauthenticated(pointer, ptrauth_key_function_pointer, 0);
#endif
        s_set_scale_z = (void (*)(void *, float))pointer;
    }
    xrc_logi(XRCLC_BOOT, @"practice-adapt v1: flow=1/r offset=r setter=%d window=%d",
             s_setter_valid, xrc_feature_complete("rate_flow"));
}
void xrc_rate_adapt_set_offset(bool enabled) { atomic_store(&s_offset_enabled, enabled); }
void xrc_rate_adapt_set_flow(bool enabled) { atomic_store(&s_flow_enabled, enabled); }
bool xrc_rate_adapt_offset_enabled(void) { return atomic_load(&s_offset_enabled); }
bool xrc_rate_adapt_flow_enabled(void) { return atomic_load(&s_flow_enabled); }
bool xrc_rate_adapt_flow_available(void) {
    return s_setter_valid && xrc_feature_complete("rate_flow");
}
int32_t xrc_rate_adapt_offset_extra(void *ng) {
    return (uint64_t)ng == s_ng ? s_extra : 0;
}
static void s_flow_frame(void *scene, void *ng) {
    uint64_t node = s_u64((uint64_t)scene + 880);
    uint64_t vtable = node ? s_u64(node) : 0;
    if (!node || vtable != xrc_image_base() + XRC_OFF_RENDER_ROOT_VPTR || !s_setter_valid) {
        atomic_store(&s_window_rate, 1000);
        atomic_store(&s_window_ng, 0);
        return;
    }
    float current = 1.0f;
    if (!s_read(node + 52, &current, sizeof(current)) || !isfinite(current)) return;
    if (node != s_node) { s_node = node; s_scaled = false; }
    // Preserve native scene/challenge transformations rather than cumulatively
    // multiplying the value written in our previous frame.
    if (!s_scaled || !xrc_adapt_same_scale(current, s_last_z)) s_base_z = current;
    bool enabled = xrc_rate_adapt_flow_enabled() && xrc_rate_adapt_flow_available();
    double rate = xrc_adapt_rate(xrc_clock_get_rate());
    float desired = (float)(s_base_z * xrc_adapt_flow_factor(rate, enabled));
    if (!xrc_adapt_same_scale(current, desired)) s_set_scale_z((void *)node, desired);
    s_last_z = desired; s_scaled = enabled;
    atomic_store(&s_window_ng, (uint64_t)ng);
    atomic_store(&s_window_rate, enabled ? (uint32_t)llround(rate * 1000.0) : 1000);
}
void xrc_rate_adapt_frame_begin(void *scene, void *ng) {
    if (!scene || !ng || xrc_gameplay_seek_active()) return;
    uint64_t clock = s_u64((uint64_t)ng + XRC_CLOCK_IN_NOTEGROUP_OFF);
    uint64_t song = s_u64((uint64_t)scene + 728);
    if (!clock) return;
    if (s_scene != (uint64_t)scene || s_ng != (uint64_t)ng || s_clock != clock || s_song != song) {
        s_scene = (uint64_t)scene; s_ng = (uint64_t)ng; s_clock = clock; s_song = song;
        s_original_offset = s_preference_offset(); s_extra = 0;
        s_node = 0; s_scaled = false;
    }
    int32_t desired = xrc_adapt_offset_extra(s_original_offset, xrc_clock_get_rate(),
                                            xrc_rate_adapt_offset_enabled());
    if (desired != s_extra) {
        int32_t old_base = 0;
        if (s_read(clock + XRC_CLK_BASE_OFF, &old_base, sizeof(old_base))) {
            int32_t updated = xrc_adapt_add(old_base, (int64_t)desired - s_extra);
            int64_t applied = (int64_t)updated - old_base + s_extra;
            if (applied >= INT_MIN && applied <= INT_MAX) {
                *(int32_t *)(clock + XRC_CLK_BASE_OFF) = updated;
                s_extra = (int32_t)applied;
                xrc_logi(XRCLC_BOOT, @"[adapt] offset base=%d extra=%d rate=%.3f enabled=%d",
                    s_original_offset, s_extra, xrc_clock_get_rate(), xrc_rate_adapt_offset_enabled());
            }
        }
    }
    s_flow_frame(scene, ng);
}
void xrc_rate_adapt_frame_end(void *scene, void *ng) {
    if (scene && ng && !xrc_gameplay_seek_active()) s_flow_frame(scene, ng);
}
void xrc_rate_adapt_window(void *context) {
    ucontext_t *uc = context;
    if (!uc || !uc->uc_mcontext) return;
    __typeof__(uc->uc_mcontext->__ss) *ss = &uc->uc_mcontext->__ss;
    if (ss->__x[19] != atomic_load(&s_window_ng)) return;
    uint32_t rate = atomic_load(&s_window_rate);
    if (rate == 1000) return;
    uint64_t sp = (uint64_t)__darwin_arm_thread_state64_get_sp(*ss);
    // Common join after both the default and special-scene window paths.
    int32_t *front = (int32_t *)(sp + 0x34), *back = (int32_t *)(sp + 0x38);
    *front = xrc_adapt_window_units(*front, rate);
    *back = xrc_adapt_window_units(*back, rate);
}
