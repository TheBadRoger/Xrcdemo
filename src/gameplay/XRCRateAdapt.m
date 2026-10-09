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
static _Atomic(int32_t) s_manual_flow, s_auto_base, s_desired_units;
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
static void s_save_base(int32_t base) {
    NSMutableDictionary *p=xrc_config_dict();p[@"nativeFlowBase"]=@(base);xrc_config_write_dict(p);
}
static void s_update_desired(void) {
    int32_t base=atomic_load(&s_manual_flow);
    bool adapt=atomic_load(&s_flow_enabled);
    if (!base && adapt) base=atomic_load(&s_auto_base);
    atomic_store(&s_desired_units,xrc_flow_value(base,xrc_clock_get_rate(),adapt));
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
    int64_t saved=[xrc_config_dict()[@"nativeFlowBase"] longLongValue];
    if (saved>0 && saved<=INT_MAX) atomic_store(&s_auto_base,(int32_t)saved);
    xrc_logi(XRCLC_BOOT,@"practice-adapt v1; practice-live-flow v1; practice-value-flow v1: native highspeed_int only setter=%d",s_setter_valid);
    xrc_rate_adapt_native_tick();
}
void xrc_rate_adapt_set_offset(bool enabled) { atomic_store(&s_offset_enabled,enabled); }
void xrc_rate_adapt_set_flow(bool enabled) {
    bool previous=atomic_exchange(&s_flow_enabled,enabled);
    if (previous && !enabled && [NSThread isMainThread]) {
        int32_t base=atomic_load(&s_manual_flow);
        if (!base) base=atomic_load(&s_auto_base);
        atomic_store(&s_desired_units,base);
        uint64_t p=s_settings();
        if (base && p && s_setter_valid) s_set_flow((void *)p,base);
        atomic_store(&s_auto_base,0);s_save_base(0);
    }
    s_update_desired();
    if (s_setter_valid && [NSThread isMainThread]) xrc_rate_adapt_native_tick();
}
bool xrc_rate_adapt_offset_enabled(void) { return atomic_load(&s_offset_enabled); }
bool xrc_rate_adapt_flow_enabled(void) { return atomic_load(&s_flow_enabled); }
bool xrc_rate_adapt_flow_available(void) { return s_setter_valid && xrc_feature_complete("rate_flow"); }
void xrc_rate_adapt_native_tick(void) {
    if (![NSThread isMainThread] || !xrc_rate_adapt_flow_available()) return;
    if (atomic_load(&s_flow_enabled) && !atomic_load(&s_auto_base)) {
        int32_t base=atomic_load(&s_manual_flow);
        if (!base) base=s_native_units();
        if (base) { atomic_store(&s_auto_base,base);s_save_base(base); }
    }
    s_update_desired();
    int32_t desired=atomic_load(&s_desired_units);
    if (!desired) return;
    uint64_t p=s_settings();int32_t current=0;
    if (!p || !s_read(p+12,&current,4) || current==desired) return;
    s_set_flow((void *)p,desired);
    if (!s_read(p+12,&current,4) || current!=desired)
        xrc_logw(XRCLC_BOOT,@"[flow-native] value write mismatch desired=%d actual=%d",desired,current);
}
// This site is the actual Preferences setter's STR W1,[X0,#12], not a draw result.
void xrc_rate_adapt_preference_write(void *context) {
    ucontext_t *uc=context;if (!uc || !uc->uc_mcontext) return;
    int32_t desired=atomic_load(&s_desired_units);
    uc->uc_mcontext->__ss.__x[1]=(uint32_t)xrc_flow_write_value(desired,(int32_t)uc->uc_mcontext->__ss.__x[1]);
}
bool xrc_rate_adapt_set_manual_flow(double speed) {
    uint64_t units=0;
    if (speed!=0 && !xrc_live_flow_units(speed,&units)) return false;
    atomic_store(&s_manual_flow,(int32_t)units);s_update_desired();
    if (s_setter_valid && [NSThread isMainThread]) {
        xrc_rate_adapt_native_tick();
        return !units || s_native_units()==atomic_load(&s_desired_units);
    }
    return true;
}
double xrc_rate_adapt_manual_flow(void) { return atomic_load(&s_manual_flow)/10.0; }
double xrc_rate_adapt_base_flow(void) {
    int32_t base=atomic_load(&s_manual_flow);
    if (!base && atomic_load(&s_flow_enabled)) base=atomic_load(&s_auto_base);
    return (base ? base : s_native_units())/10.0;
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
    int32_t desired=atomic_load(&s_desired_units);
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
