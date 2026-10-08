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
#include "XRCConfig.h"
#import "XRCLog.h"

extern uint64_t xrc_image_base(void);
static _Atomic(bool) s_offset_enabled, s_flow_enabled, s_native_update;
static _Atomic(uint64_t) s_native_ng, s_factor_bits;
static _Atomic(int32_t) s_manual_flow, s_bucket_min, s_bucket_max;
static uint64_t s_scene, s_ng, s_clock, s_song, s_bounds_ng;
static int32_t s_original_offset, s_extra;
static bool s_setter_valid;
static void (*s_set_flow)(void *, int32_t);
static uint64_t s_applied_settings;
static uint64_t s_failed_bounds_ng;
static int32_t s_applied_units;
static double s_reported_factor;

static bool s_read(uint64_t address, void *out, size_t size) {
    vm_size_t read = 0;
    return address && vm_read_overwrite(mach_task_self(), address, size,
        (vm_address_t)out, &read) == KERN_SUCCESS && read == size;
}
static uint64_t s_u64(uint64_t address) {
    uint64_t value = 0; s_read(address, &value, sizeof(value)); return value;
}
static uint64_t s_settings(void) {
    uint64_t app=s_u64(xrc_image_base()+XRC_OFF_APP_GLOBAL);
    return app ? s_u64(app+112) : 0;
}
static int32_t s_native_units(void) {
    int32_t units=0; uint64_t settings=s_settings();
    if (settings) s_read(settings+12,&units,sizeof(units));
    return units > 0 ? units : 0;
}
static int32_t s_preference_offset(void) {
    uint64_t preferences=s_settings();
    int32_t fields[3]={0};
    if (!preferences || !s_read(preferences,fields,sizeof(fields))) return 0;
    return fields[fields[0] ? 2 : 1];
}
void xrc_rate_adapt_install(void) {
    uint64_t function=xrc_image_base()+XRC_OFF_FLOW_SETTER;
    const unsigned char fingerprint[4]={0xf4,0x4f,0xbe,0xa9};
    unsigned char actual[4];
    s_setter_valid=s_read(function,actual,sizeof(actual)) && !memcmp(actual,fingerprint,sizeof(actual));
    if (s_setter_valid) {
        void *pointer=(void *)function;
#if __has_feature(ptrauth_calls)
        pointer=ptrauth_sign_unauthenticated(pointer,ptrauth_key_function_pointer,0);
#endif
        s_set_flow=(void (*)(void *,int32_t))pointer;
    }
    xrc_logi(XRCLC_BOOT,@"practice-adapt v1: offset=r; native flow compensation available=%d",xrc_feature_complete("rate_flow"));
    xrc_logi(XRCLC_BOOT,@"practice-live-flow v1: native highspeed_int setter=%d",s_setter_valid);
    xrc_logi(XRCLC_BOOT,@"practice-native-flow v1: relative note distance only; node scale and display thresholds untouched");
    xrc_rate_adapt_native_tick();
}
void xrc_rate_adapt_set_offset(bool enabled) { atomic_store(&s_offset_enabled,enabled); }
void xrc_rate_adapt_set_flow(bool enabled) { atomic_store(&s_flow_enabled,enabled); }
bool xrc_rate_adapt_offset_enabled(void) { return atomic_load(&s_offset_enabled); }
bool xrc_rate_adapt_flow_enabled(void) { return atomic_load(&s_flow_enabled); }
bool xrc_rate_adapt_flow_available(void) { return s_setter_valid && xrc_feature_complete("rate_flow"); }
void xrc_rate_adapt_native_tick(void) {
    if (![NSThread isMainThread] || !xrc_rate_adapt_flow_available()) return;
    int32_t requested=atomic_load(&s_manual_flow);
    if (!requested) return;
    uint64_t settings=s_settings();
    int32_t current=0;
    if (!settings || !s_read(settings+12,&current,sizeof(current))) return;
    if (settings==s_applied_settings && requested==s_applied_units) {
        if (current>0 && current!=requested) {
            // Native settings changes take precedence over our saved request.
            atomic_store(&s_manual_flow,0);
            s_applied_settings=0;
            xrc_config_t config; xrc_config_load(&config);
            config.manual_note_flow=0; xrc_config_save(&config);
            xrc_logi(XRCLC_BOOT,@"[flow-native] game settings changed to %.1f",current/10.0);
        }
        return;
    }
    @try { s_set_flow((void *)settings,requested); }
    @catch (NSException *exception) { xrc_logw(XRCLC_BOOT,@"[flow-native] setter exception: %@",exception); return; }
    if (!s_read(settings+12,&current,sizeof(current)) || current!=requested) {
        xrc_logw(XRCLC_BOOT,@"[flow-native] setter readback mismatch requested=%d actual=%d",requested,current);
        return;
    }
    s_applied_settings=settings; s_applied_units=requested;
    xrc_logi(XRCLC_BOOT,@"[flow-native] saved native flow %.1f",requested/10.0);
}
bool xrc_rate_adapt_set_manual_flow(double speed) {
    uint64_t units=0;
    if (speed!=0 && !xrc_live_flow_units(speed,&units)) return false;
    atomic_store(&s_manual_flow,(int32_t)units);
    s_applied_settings=0;
    if (units && s_setter_valid && [NSThread isMainThread]) {
        xrc_rate_adapt_native_tick();
        return s_applied_units==(int32_t)units && s_applied_settings!=0;
    }
    return true; // bootstrap may queue before app preferences are initialized
}
double xrc_rate_adapt_manual_flow(void) { return atomic_load(&s_manual_flow)/10.0; }
double xrc_rate_adapt_native_flow(void) { return s_native_units()/10.0; }
int32_t xrc_rate_adapt_offset_extra(void *ng) { return (uint64_t)ng==s_ng ? s_extra : 0; }

// Record the existing native bucket key range; never rebuild maps or write their keys.
static bool s_capture_bucket_bounds(uint64_t ng) {
    uint64_t begin=s_u64(ng+136),end=s_u64(ng+144);
    if (!begin || end<=begin || (end-begin)%8 || end-begin>256*8) return false;
    int32_t lower=INT_MAX,upper=INT_MIN;
    for (uint64_t item=begin;item<end;item+=8) {
        uint64_t map=s_u64(item),root=map ? s_u64(map+8) : 0;
        if (!root) continue;
        for (int direction=0;direction<2;++direction) {
            uint64_t node=root;
            for (int depth=0;depth<64;++depth) {
                int32_t key=0; uint64_t child=0;
                if (!s_read(node+32,&key,sizeof(key)) || !s_read(node+direction*8,&child,sizeof(child))) return false;
                if (key<lower) lower=key; if (key>upper) upper=key;
                if (!child) break;
                node=child;
                if (depth==63) return false;
            }
        }
    }
    if (lower>upper) return false;
    atomic_store(&s_bucket_min,xrc_adapt_add(lower,-2));
    atomic_store(&s_bucket_max,xrc_adapt_add(upper,2));
    s_bounds_ng=ng; return true;
}
static void s_flow_frame(void *scene,void *ng) {
    (void)scene;
    xrc_rate_adapt_native_tick();
    uint64_t chart=s_u64((uint64_t)ng+40);
    float baseline=0;
    if (!xrc_rate_adapt_flow_available() || !chart || !s_read(chart+240,&baseline,sizeof(baseline)) || !isfinite(baseline) || baseline<=0) return;
    if (s_bounds_ng!=(uint64_t)ng && !s_capture_bucket_bounds((uint64_t)ng)) {
        if (s_failed_bounds_ng!=(uint64_t)ng) {
            xrc_logw(XRCLC_BOOT,@"[flow-native] native bucket bounds unavailable; distance update deferred");
            s_failed_bounds_ng=(uint64_t)ng;
        }
        return;
    }
    s_failed_bounds_ng=0;
    double native=xrc_rate_adapt_native_flow();
    double factor=xrc_live_flow_factor(baseline,native,xrc_clock_get_rate(),xrc_rate_adapt_flow_enabled());
    uint64_t bits; memcpy(&bits,&factor,sizeof(bits));
    atomic_store(&s_factor_bits,bits); atomic_store(&s_native_ng,(uint64_t)ng);
    if (factor!=s_reported_factor) {
        xrc_logi(XRCLC_BOOT,@"[flow-native] loaded=%.6f setting=%.1f rate=%.3f distance-factor=%.8g adapt=%d",
            baseline,native,xrc_clock_get_rate(),factor,xrc_rate_adapt_flow_enabled());
        s_reported_factor=factor;
    }
}
void xrc_rate_adapt_frame_begin(void *scene, void *ng) {
    atomic_store(&s_native_update, false);
    atomic_store(&s_native_ng, 0);
    if (!scene || !ng || xrc_gameplay_seek_active()) return;
    uint64_t clock = s_u64((uint64_t)ng + XRC_CLOCK_IN_NOTEGROUP_OFF);
    uint64_t song = s_u64((uint64_t)scene + 728);
    if (!clock) return;
    if (s_scene != (uint64_t)scene || s_ng != (uint64_t)ng || s_clock != clock || s_song != song) {
        s_scene = (uint64_t)scene; s_ng = (uint64_t)ng; s_clock = clock; s_song = song;
        s_original_offset = s_preference_offset(); s_extra = 0;
        s_bounds_ng = 0;
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

void xrc_rate_adapt_native_begin(void *ng) {
    atomic_store(&s_native_update,ng && (uint64_t)ng==atomic_load(&s_native_ng) && !xrc_gameplay_seek_active());
}
void xrc_rate_adapt_frame_end(void *scene,void *ng) {
    (void)scene; (void)ng; atomic_store(&s_native_update,false);
}
static double s_signal_factor(void) {
    if (!atomic_load(&s_native_update)) return 1;
    uint64_t bits=atomic_load(&s_factor_bits); double factor;
    memcpy(&factor,&bits,sizeof(factor)); return factor;
}
static void s_distance(void *context,int reg) {
    ucontext_t *uc=context;
    if (!uc || !uc->uc_mcontext) return;
    double factor=s_signal_factor(); if (factor==1) return;
    float lanes[2]; memcpy(lanes,&uc->uc_mcontext->__ns.__v[reg],sizeof(lanes));
    lanes[0]=xrc_native_flow_distance(lanes[0],factor);
    lanes[1]=xrc_native_flow_distance(lanes[1],factor);
    memcpy(&uc->uc_mcontext->__ns.__v[reg],lanes,sizeof(lanes));
}
void xrc_rate_adapt_note(void *context) { s_distance(context,0); }
void xrc_rate_adapt_arc(void *context) { s_distance(context,1); }
static void s_candidates(void *context,bool upper) {
    ucontext_t *uc=context;
    if (!uc || !uc->uc_mcontext) return;
    double factor=s_signal_factor(); if (factor>=1) return;
    __typeof__(uc->uc_mcontext->__ss) *ss=&uc->uc_mcontext->__ss;
    uint64_t ng=atomic_load(&s_native_ng); if (ss->__x[19]!=ng) return;
    float index=0,window=0;
    memcpy(&index,&uc->uc_mcontext->__ns.__v[0],sizeof(index));
    if (upper) window=*(const int32_t *)(ng+24);
    else memcpy(&window,&uc->uc_mcontext->__ns.__v[9],sizeof(window));
    index=xrc_native_flow_candidate(index,window,factor,upper,atomic_load(&s_bucket_min),atomic_load(&s_bucket_max));
    memcpy(&uc->uc_mcontext->__ns.__v[0],&index,sizeof(index));
}
void xrc_rate_adapt_lower(void *context) { s_candidates(context,false); }
void xrc_rate_adapt_upper(void *context) { s_candidates(context,true); }
void xrc_rate_adapt_window(void *context) { (void)context; } // retired hook: no window writes
