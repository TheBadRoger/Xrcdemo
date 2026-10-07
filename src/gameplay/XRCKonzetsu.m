#define _XOPEN_SOURCE 700
#include <ucontext.h>
#undef _XOPEN_SOURCE
#include <mach/arm/thread_status.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include "XRCKonzetsu.h"
#include "XRCKonzetsuMath.h"
#include "XRCProfile.h"
#include "XRCHook.h"
#import "XRCLog.h"

extern uint64_t xrc_image_base(void);
static _Atomic(uint32_t) s_requested = 1, s_round;
static _Atomic(uint64_t) s_chart;
static _Atomic(uint32_t) s_duration, s_round_seq, s_info_seq, s_alloc_fail;
static _Atomic(bool) s_ready;
static uint32_t s_logged_round, s_logged_info, s_logged_fail;

void xrc_konzetsu_configure(int id, bool effects, bool gauge) {
    atomic_store(&s_requested, xrc_konzetsu_options(id, effects, gauge));
}
bool xrc_konzetsu_available(void) {
#if defined(XRC_GAME_VERSION_7_0_256)
    return xrc_feature_complete("konzetsu");
#else
    return false;
#endif
}
uint32_t xrc_konzetsu_round_options(void) { return atomic_load(&s_round); }

void xrc_konzetsu_tick(void) {
    atomic_store(&s_ready, xrc_konzetsu_available());
    uint32_t seq = atomic_load(&s_round_seq);
    if (seq != s_logged_round) {
        s_logged_round = seq;
        uint32_t round = atomic_load(&s_round);
        xrc_logi(XRCLC_BOOT, @"[konzetsu] round=%u selection=%u effects=%d gauge=%d span=%u chart=%llx",
                 seq, round & 0xff, xrc_konzetsu_effects(round),
                 xrc_konzetsu_gauge(round), atomic_load(&s_duration), atomic_load(&s_chart));
    }
    seq = atomic_load(&s_info_seq);
    if (seq != s_logged_info) {
        s_logged_info = seq;
        xrc_logi(XRCLC_BOOT, @"[konzetsu] generated combined schedule calls=%u span=%u",
                 seq, atomic_load(&s_duration));
    }
    seq = atomic_load(&s_alloc_fail);
    if (seq != s_logged_fail) {
        s_logged_fail = seq;
        xrc_logw(XRCLC_BOOT, @"[konzetsu] combined schedule allocation failed (%u)", seq);
    }
}

#if defined(XRC_GAME_VERSION_7_0_256)
typedef __typeof__(((ucontext_t *)0)->uc_mcontext->__ss) xrc_konzetsu_registers_t;
static xrc_konzetsu_registers_t *s_registers(void *context) {
    ucontext_t *uc = context;
    return uc && uc->uc_mcontext ? &uc->uc_mcontext->__ss : NULL;
}
static bool s_pointer(uint64_t p) { return p >= 0x100000000ULL && !(p & 7); }
static uint32_t s_native_id(void) {
    uint64_t app = *(const uint64_t *)(xrc_image_base() + XRC_OFF_APP_GLOBAL);
    uint64_t manager = s_pointer(app) ? *(const uint64_t *)(app + 224) : 0;
    return s_pointer(manager) ? *(const uint32_t *)(manager + 56) : 0;
}
static bool s_practice(void) {
    return atomic_load(&s_ready) && xrc_konzetsu_effects(atomic_load(&s_round))
        && s_native_id() == 0;
}
static uint64_t s_caller(xrc_konzetsu_registers_t *ss) {
    return (uint64_t)__darwin_arm_thread_state64_get_lr(*ss) - xrc_image_base();
}
static bool s_between(uint64_t caller, uint64_t begin, uint64_t end) {
    return caller > begin && caller <= end;
}
static bool s_effect_caller(uint64_t caller) {
    // Only chart conversion and renderer construction; no menus/results/checkpoints.
    return s_between(caller, 0x910CE0, 0x912E54)
        || s_between(caller, 0xB25128, 0xB2557C);
}
static bool s_gauge_caller(uint64_t caller) {
    return s_between(caller, 0xC4ADB4, 0xC4B114)
        || s_between(caller, 0xC4B9A4, 0xC4BC70)
        || s_between(caller, 0xBAAD08, 0xBAEAF8);
}
static void s_return(xrc_konzetsu_registers_t *ss, uint32_t value) {
    ss->__x[0] = value;
    __darwin_arm_thread_state64_set_pc_fptr(*ss,
        (void *)__darwin_arm_thread_state64_get_lr(*ss));
}

void xrc_konzetsu_chart(void *context) {
    xrc_konzetsu_registers_t *ss = s_registers(context);
    if (!ss) return;
    // setupNotesFromParsed: x0=LogicChart, x1=ParsedSong. Snapshot once per load.
    uint32_t options = atomic_load(&s_requested);
    atomic_store(&s_chart, ss->__x[0]);
    atomic_store(&s_duration, 0);
    if (!atomic_load(&s_ready) || !s_pointer(ss->__x[1]) || s_native_id()) options = 0;
    uint64_t parsed = ss->__x[1];
    uint32_t span = 0;
    if (xrc_konzetsu_effects(options)) {
        uint64_t begin = *(const uint64_t *)(parsed + 24);
        uint64_t end = *(const uint64_t *)(parsed + 32);
        if (s_pointer(begin) && end >= begin && !(end & 7) && end - begin <= 800000) {
            for (uint64_t p = begin; p < end; p += 8) {
                uint64_t note = *(const uint64_t *)p;
                if (!s_pointer(note)) continue;
                int32_t time = *(const int32_t *)(note + 24);
                if (time > 0 && time <= 1199500 && (uint32_t)time > span) span = time;
            }
        }
        // The last start plus a short tail is stable before native note conversion.
        if (span) span += 500;
        if (span < 1000) options = 0;
    }
    atomic_store(&s_duration, span);
    atomic_store(&s_round, options);
    atomic_fetch_add(&s_round_seq, 1);
}

void xrc_konzetsu_id(void *context) {
    xrc_konzetsu_registers_t *ss = s_registers(context);
    if (!ss || !s_practice()) return; // native getter instruction is replayed
    uint64_t caller = s_caller(ss);
    if (s_effect_caller(caller) || s_gauge_caller(caller)) {
        uint32_t options = atomic_load(&s_round);
        // UILayer only creates the clickable gauge in challenge-gauge mode.
        uint32_t id = s_between(caller, 0xBAAD08, 0xBAEAF8)
            && !xrc_konzetsu_gauge(options) ? 0 : xrc_konzetsu_native_id(options & 0xff);
        s_return(ss, id);
    }
}
void xrc_konzetsu_active(void *context) {
    xrc_konzetsu_registers_t *ss = s_registers(context);
    if (ss && s_practice() && s_between(s_caller(ss), 0xC4ADB4, 0xC4B114)) s_return(ss, 1);
}
void xrc_konzetsu_score(void *context) {
    xrc_konzetsu_registers_t *ss = s_registers(context);
    // ScoreState owns all lifebar types: select the active type, don't rewrite every bar.
    if (ss && s_practice() && ss->__x[1] == atomic_load(&s_chart))
        ss->__x[2] = xrc_konzetsu_gauge(atomic_load(&s_round)) ? 11 : 2;
}
void xrc_konzetsu_hpbar(void *context) {
    xrc_konzetsu_registers_t *ss = s_registers(context);
    // UILayer::init: x5=PlayModifier. Scope the gauge at gameplay UI construction,
    // not HPBar::init (the latter is also used by menu/result previews).
    if (ss && s_practice())
        ss->__x[5] = xrc_konzetsu_gauge(atomic_load(&s_round)) ? 11 : 2;
}

// libc++ std::vector<pair<int,int>> on this ABI is three pointers; native callers
// move/free these allocations. Each invocation must own a fresh set of buffers.
typedef struct { xrc_konzetsu_interval_t *begin, *end, *capacity; } xrc_native_intervals_t;
_Static_assert(sizeof(xrc_native_intervals_t) == 24, "native vector ABI");

static void *s_make_info(void *result, uint32_t duration) {
    static const xrc_konzetsu_interval_t pattern[4][4] = {
        {{23200,33600},{74000,82700},{121100,129600},{0,0}}, // speed
        {{34300,43600},{64700,72000},{98400,101000},{132200,137200}}, // inversion
        {{12700,22000},{54500,64200},{112400,121000},{145300,150300}}, // hidden
        {{43700,86900},{87000,104900},{105000,145300},{145400,150200}} // drain/tap
    };
    xrc_native_intervals_t *vectors = result;
    memset(result, 0, 96);
    for (int i = 0; i < 4; i++) {
        size_t count = i == 0 ? 3 : 4;
        xrc_konzetsu_interval_t *buffer = malloc(count * sizeof(*buffer));
        if (!buffer) {
            for (int j = 0; j < i; j++) free(vectors[j].begin);
            memset(result, 0, 96);
            atomic_fetch_add(&s_alloc_fail, 1);
            return result;
        }
        for (size_t j = 0; j < count; j++)
            xrc_konzetsu_scale_interval(pattern[i][j], duration, &buffer[j]);
        vectors[i] = (xrc_native_intervals_t){buffer, buffer + count, buffer + count};
    }
    atomic_fetch_add(&s_info_seq, 1);
    return result;
}
static bool s_original_final_song(uint64_t value) {
    if (!s_pointer(value)) return false;
    // libc++ string short layout: chars at +0, length/tag at +23; long chars at +0 pointer.
    const unsigned char *object = (const unsigned char *)value;
    bool long_string = (int8_t)object[23] < 0;
    const char *text = long_string ? *(const char *const *)object : (const char *)object;
    size_t length = long_string ? *(const size_t *)(object + 8) : object[23];
    if (!text || length > 32) return false;
    static const char *const songs[] = {"arghena", "cataclysmcry", "rivenpilgrim", "un"};
    for (int i = 0; i < 4; i++)
        if (length == strlen(songs[i]) && !memcmp(text, songs[i], length)) return true;
    return false;
}
void xrc_konzetsu_info(void *context) {
    xrc_konzetsu_registers_t *ss = s_registers(context);
    if (!ss || !s_practice() || (atomic_load(&s_round) & 0xff) != 6
        || s_original_final_song(ss->__x[1])) return;
    uint64_t caller = s_caller(ss);
    if (!(s_effect_caller(caller) || s_between(caller, 0xC4ADB4, 0xC4B114))
        || !s_pointer(ss->__x[8])) return;
    // Enter a normal C function only AFTER sigreturn. No malloc/engine calls in SIGTRAP.
    // The intercepted function uses x8 for the 96-byte aggregate return; C bridge uses x0.
    ss->__x[0] = ss->__x[8];
    ss->__x[1] = atomic_load(&s_duration);
    __darwin_arm_thread_state64_set_pc_fptr(*ss, (void *)s_make_info);
}
#else
void xrc_konzetsu_chart(void *context) { (void)context; }
void xrc_konzetsu_id(void *context) { (void)context; }
void xrc_konzetsu_active(void *context) { (void)context; }
void xrc_konzetsu_score(void *context) { (void)context; }
void xrc_konzetsu_hpbar(void *context) { (void)context; }
void xrc_konzetsu_info(void *context) { (void)context; }
#endif
