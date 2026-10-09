#define _XOPEN_SOURCE 700
#include <ucontext.h>
#undef _XOPEN_SOURCE
#include <mach/mach.h>
#include <mach/arm/thread_status.h>
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
#include "XRCAudio.h"
#import "XRCLog.h"
extern uint64_t xrc_image_base(void);
static _Atomic(bool) s_offset_enabled, s_flow_enabled;
static _Atomic(int32_t) s_shared_units;
static _Atomic(double) s_auto_base;
static _Atomic(bool) s_flow_dirty;
static _Atomic(bool) s_internal_write;
static _Atomic(uint64_t) s_flow_settings;
static uint64_t s_scene,s_ng,s_clock,s_song;
static int32_t s_original_offset,s_extra;
static bool s_setter_valid;
static void (*s_set_flow)(void *,int32_t);
static bool s_read(uint64_t address,void *out,size_t size) {
    vm_size_t copied=0;
    return address && vm_read_overwrite(mach_task_self(),address,size,(vm_address_t)out,&copied)==KERN_SUCCESS && copied==size;
}
static uint64_t s_u64(uint64_t address) { uint64_t v=0;s_read(address,&v,8);return v; }
static uint64_t s_settings(void) {
    uint64_t app=s_u64(xrc_image_base()+XRC_OFF_APP_GLOBAL);
    return app ? s_u64(app+112) : 0;
}
static int32_t s_native_units(void) {
    int32_t value=0;s_read(s_settings()+12,&value,4);return value>0 ? value : 0;
}
static int32_t s_preference_offset(void) {
    uint64_t p=s_settings();int32_t f[3]={0};
    return p && s_read(p,f,sizeof(f)) ? f[f[0] ? 2 : 1] : 0;
}
// Both interfaces commit to Preferences+12; the base is only an adaptive reference.
static void s_accept_flow(int32_t value) {
    if (value<=0) return;
    atomic_store(&s_shared_units,value);
    atomic_store(&s_auto_base,xrc_flow_base_for_value(value,xrc_clock_get_rate(),xrc_rate_adapt_flow_enabled()));
    atomic_store(&s_flow_dirty,true);
}
static bool s_write_flow(uint64_t settings,int32_t value) {
    if (!settings || !s_setter_valid || value<=0) return false;
    atomic_store(&s_flow_settings,settings);
    atomic_store(&s_internal_write,true);
    s_set_flow((void *)settings,value);
    atomic_store(&s_internal_write,false);
    int32_t actual=0;
    if (!s_read(settings+12,&actual,4) || actual!=value) return false;
    atomic_store(&s_shared_units,actual);atomic_store(&s_flow_dirty,true);
    return true;
}
static void s_save_flow(void) {
    if (!atomic_exchange(&s_flow_dirty,false)) return;
    NSMutableDictionary *p=xrc_config_dict();
    p[@"nativeFlowBase"]=@(atomic_load(&s_auto_base));
    p[@"nativeFlowValue"]=@(atomic_load(&s_shared_units));
    xrc_config_write_dict(p);
}
void xrc_rate_adapt_install(void) {
    uint64_t f=xrc_image_base()+XRC_OFF_FLOW_SETTER;
    const unsigned char expected[]={0xf4,0x4f,0xbe,0xa9};unsigned char actual[4];
    s_setter_valid=s_read(f,actual,4) && !memcmp(actual,expected,4);
    if (s_setter_valid) {
        void *p=(void *)f;
#if __has_feature(ptrauth_calls)
        p=ptrauth_sign_unauthenticated(p,ptrauth_key_function_pointer,0);
#endif
        s_set_flow=(void (*)(void *,int32_t))p;
    }
    int32_t current=s_native_units();
    NSDictionary *saved=xrc_config_dict();
    double base=[saved[@"nativeFlowBase"] doubleValue];
    if (current>0) {
        atomic_store(&s_shared_units,current);
        atomic_store(&s_auto_base,isfinite(base) && base>0 && [saved[@"nativeFlowValue"] intValue]==current ? base : current);
    }
    xrc_logi(XRCLC_BOOT,@"practice-adapt v1; practice-live-flow v1; practice-value-flow v1; practice-shared-flow v1: native highspeed_int shared setter=%d",s_setter_valid);
    xrc_rate_adapt_native_tick();
}
void xrc_rate_adapt_set_offset(bool enabled) { atomic_store(&s_offset_enabled,enabled); }
void xrc_rate_adapt_set_flow(bool enabled) {
    bool previous=atomic_exchange(&s_flow_enabled,enabled);
    if (previous==enabled || !s_setter_valid || ![NSThread isMainThread]) return;
    int32_t current=s_native_units();
    // Enabling starts from the current shared value; disabling leaves that value intact.
    if (current>0) {
        atomic_store(&s_shared_units,current);atomic_store(&s_auto_base,(double)current);
        atomic_store(&s_flow_dirty,true);
    }
    xrc_rate_adapt_native_tick();
}
bool xrc_rate_adapt_offset_enabled(void) { return atomic_load(&s_offset_enabled); }
bool xrc_rate_adapt_flow_enabled(void) { return atomic_load(&s_flow_enabled); }
bool xrc_rate_adapt_flow_available(void) { return s_setter_valid && xrc_feature_complete("rate_flow"); }
void xrc_rate_adapt_native_tick(void) {
    if (![NSThread isMainThread] || !xrc_rate_adapt_flow_available()) return;
    uint64_t settings=s_settings();int32_t current=0;
    if (!settings || !s_read(settings+12,&current,4) || current<=0) return;
    atomic_store(&s_flow_settings,settings);
    // Also adopt game writes which bypassed its setter, rather than overwrite them.
    if (current!=atomic_load(&s_shared_units)) s_accept_flow(current);
    if (xrc_rate_adapt_flow_enabled()) {
        double base=atomic_load(&s_auto_base);
        if (base<=0) { base=current;atomic_store(&s_auto_base,base); }
        int32_t desired=xrc_flow_value(base,xrc_clock_get_rate(),true);
        if (desired!=current && !s_write_flow(settings,desired))
            xrc_logw(XRCLC_BOOT,@"[flow-native] shared value write failed desired=%d",desired);
    }
    s_save_flow();
}
// Observe the actual setter; never substitute the game's requested W1 value.
void xrc_rate_adapt_preference_write(void *context) {
    ucontext_t *uc=context;if (!uc || !uc->uc_mcontext || atomic_load(&s_internal_write)) return;
    uint64_t settings=atomic_load(&s_flow_settings);
    if (settings && uc->uc_mcontext->__ss.__x[0]!=settings) return;
    s_accept_flow((int32_t)uc->uc_mcontext->__ss.__x[1]);
}
bool xrc_rate_adapt_set_native_flow(double speed) {
    uint64_t units=0;
    if (!xrc_live_flow_units(speed,&units) || ![NSThread isMainThread]) return false;
    if (!s_write_flow(s_settings(),(int32_t)units)) return false;
    s_accept_flow((int32_t)units);s_save_flow();return true;
}

double xrc_rate_adapt_native_flow(void) { return s_native_units()/10.0; }
int32_t xrc_rate_adapt_offset_extra(void *ng) { return (uint64_t)ng==s_ng ? s_extra : 0; }
void xrc_rate_adapt_frame_begin(void *scene,void *ng) {
    if (!scene || !ng || xrc_gameplay_seek_active()) return;
    // These objects belong to the current native update; avoid Mach IPC per field per frame.
    uint64_t clock=*(uint64_t *)((char *)ng+XRC_CLOCK_IN_NOTEGROUP_OFF);
    uint64_t song=*(uint64_t *)((char *)scene+728);
    if (!clock) return;
    if (s_scene!=(uint64_t)scene || s_ng!=(uint64_t)ng || s_clock!=clock || s_song!=song) {
        s_scene=(uint64_t)scene;s_ng=(uint64_t)ng;s_clock=clock;s_song=song;s_extra=0;
        xrc_rate_adapt_native_tick();
    }
    // The stored chart speed is the same native value (not a distance/geometry factor).
    int32_t desired=atomic_load(&s_shared_units);
    uint64_t chart=*(uint64_t *)((char *)ng+40);
    if (desired>0 && chart) {
        float current=*(float *)(chart+240), speed=desired/10.0f;
        if (isfinite(current) && current!=speed) *(float *)(chart+240)=speed;
    }
    s_original_offset=xrc_rate_adapt_offset_enabled() ? s_preference_offset() : 0;
    int32_t desired_offset=xrc_adapt_offset_extra(s_original_offset,xrc_clock_get_rate(),
                                                  xrc_rate_adapt_offset_enabled());
    // Music-enabled gameplay applies offset and DSP delay together in one absolute write.
    if (!xrc_audio_speed_enabled() && desired_offset!=s_extra) {
        int32_t base=0;
        if (s_read(clock+XRC_CLK_BASE_OFF,&base,4))
            *(int32_t *)(clock+XRC_CLK_BASE_OFF)=xrc_adapt_add(base,(int64_t)desired_offset-s_extra);
    }
    s_extra=desired_offset;
}
