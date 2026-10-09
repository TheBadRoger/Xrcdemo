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
static _Atomic(bool) s_enabled;
static _Atomic(int32_t) s_flow_original,s_flow_locked;
static bool s_loaded_lock;
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
static bool s_write_flow(uint64_t settings,int32_t value) {
    if (!settings || !s_setter_valid || value<=0) return false;
    atomic_store(&s_flow_settings,settings);
    s_set_flow((void *)settings,value);
    int32_t actual=0;
    if (!s_read(settings+12,&actual,4) || actual!=value) return false;
    return true;
}
// Recover the old 1x reference once before discarding the independent override keys.
static bool s_migrated_flow;
static void s_migrate_flow(uint64_t settings,int32_t current) {
    if (s_migrated_flow || current<=0) return;
    NSMutableDictionary *p=xrc_config_dict();
    if ([p[@"sharedFlowSchema"] intValue]<2) {
        uint64_t manual=0;
        double base=[p[@"nativeFlowBase"] doubleValue];
        int32_t legacy=0;
        if (xrc_live_flow_units([p[@"manualNoteFlow"] doubleValue],&manual)) legacy=(int32_t)manual;
        else if (xrc_rate_adapt_enabled() && isfinite(base) && base>0)
            legacy=base>=INT_MAX ? INT_MAX : (int32_t)fmax(1,round(base));
        if (legacy>0 && legacy!=current && !s_write_flow(settings,legacy)) return;
        [p removeObjectForKey:@"manualNoteFlow"];
        [p removeObjectForKey:@"nativeFlowBase"];
        [p removeObjectForKey:@"nativeFlowValue"];
        p[@"sharedFlowSchema"]=@2;
        xrc_config_write_dict(p);
    }
    s_migrated_flow=true;
}
static void s_save_lock(void) {
    NSMutableDictionary *p=xrc_config_dict();
    int32_t original=atomic_load(&s_flow_original), locked=atomic_load(&s_flow_locked);
    if (original>0 && locked>0) {
        p[@"flowLockOriginal"]=@(original);p[@"flowLockValue"]=@(locked);
    } else {
        [p removeObjectForKey:@"flowLockOriginal"];[p removeObjectForKey:@"flowLockValue"];
    }
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
    xrc_logi(XRCLC_BOOT,@"practice-adapt v1; practice-live-flow v1; practice-value-flow v1; practice-flow-lock v1: native highspeed_int shared setter=%d",s_setter_valid);
    xrc_rate_adapt_native_tick();
}
void xrc_rate_adapt_set_enabled(bool enabled) {
    atomic_store(&s_enabled,enabled);
    if (s_setter_valid && [NSThread isMainThread]) xrc_rate_adapt_native_tick();
}
bool xrc_rate_adapt_enabled(void) { return atomic_load(&s_enabled); }
bool xrc_rate_adapt_available(void) { return s_setter_valid && xrc_feature_complete("rate_flow"); }
void xrc_rate_adapt_native_tick(void) {
    if (![NSThread isMainThread] || !xrc_rate_adapt_available()) return;
    uint64_t settings=s_settings();int32_t current=0;
    if (!settings || !s_read(settings+12,&current,4) || current<=0) return;
    atomic_store(&s_flow_settings,settings);
    s_migrate_flow(settings,current);
    if (!s_loaded_lock) {
        NSDictionary *p=xrc_config_dict();
        int64_t original=[p[@"flowLockOriginal"] longLongValue], locked=[p[@"flowLockValue"] longLongValue];
        if (original>0 && original<=INT_MAX && locked>0 && locked<=INT_MAX) {
            atomic_store(&s_flow_original,(int32_t)original);atomic_store(&s_flow_locked,(int32_t)locked);
        }
        s_loaded_lock=true;
    }
    if (!s_read(settings+12,&current,4) || current<=0) return;
    int32_t original=atomic_load(&s_flow_original);
    if (xrc_rate_adapt_enabled()) {
        if (!original) {
            atomic_store(&s_flow_original,current);
            atomic_store(&s_flow_locked,xrc_flow_value(current,xrc_clock_get_rate(),true));
            s_save_lock(); // Save recovery before the native setting is changed.
        }
        int32_t locked=atomic_load(&s_flow_locked);
        if (current!=locked && !s_write_flow(settings,locked))
            xrc_logw(XRCLC_BOOT,@"[flow-native] locked value write failed: %d",locked);
    } else if (original) {
        if (current!=original && !s_write_flow(settings,original)) {
            xrc_logw(XRCLC_BOOT,@"[flow-native] restore original value failed: %d",original);return;
        }
        atomic_store(&s_flow_original,0);atomic_store(&s_flow_locked,0);s_save_lock();
    }
}
// While enabled, every write to the native setting receives the captured locked value.
void xrc_rate_adapt_preference_write(void *context) {
    ucontext_t *uc=context;if (!uc || !uc->uc_mcontext) return;
    uint64_t settings=atomic_load(&s_flow_settings);
    if (settings && uc->uc_mcontext->__ss.__x[0]!=settings) return;
    int32_t locked=atomic_load(&s_flow_locked);
    uc->uc_mcontext->__ss.__x[1]=(uint32_t)xrc_flow_lock_write(
        (int32_t)uc->uc_mcontext->__ss.__x[1],locked,xrc_rate_adapt_enabled());
}
bool xrc_rate_adapt_set_native_flow(double speed) {
    if (xrc_rate_adapt_enabled() || atomic_load(&s_flow_original)>0) return false;
    uint64_t units=0;
    if (!xrc_live_flow_units(speed,&units) || ![NSThread isMainThread]) return false;
    if (!s_write_flow(s_settings(),(int32_t)units)) return false;
    return true;
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
    s_original_offset=xrc_rate_adapt_enabled() ? s_preference_offset() : 0;
    int32_t desired_offset=xrc_adapt_offset_extra(s_original_offset,xrc_clock_get_rate(),
                                                  xrc_rate_adapt_enabled());
    // Music-enabled gameplay applies offset and DSP delay together in one absolute write.
    if (!xrc_audio_speed_enabled() && desired_offset!=s_extra) {
        int32_t base=0;
        if (s_read(clock+XRC_CLK_BASE_OFF,&base,4))
            *(int32_t *)(clock+XRC_CLK_BASE_OFF)=xrc_adapt_add(base,(int64_t)desired_offset-s_extra);
    }
    s_extra=desired_offset;
}
