// Arc clipping changes its CPU geometry and hides segments in one direction.
// Restore a canonical mesh before native clipping; never scale scene nodes.
#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <stdlib.h>
#include <string.h>
#include "XRCArcFlow.h"
#include "XRCRateMath.h"
#include "XRCProfile.h"
#import "XRCLog.h"
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif
extern uint64_t xrc_image_base(void);
#define ARC_SLOTS 4096
#define ARC_CHILD_LIMIT 131072
typedef struct { uint64_t node, vtable; float original[24]; bool visible; } segment_t;
typedef struct {
    uint64_t render, logic, begin, end;
    int32_t start_ms, end_ms;
    segment_t *segments;
    size_t count;
    double factor;
    bool live;
} arc_t;
static arc_t s_arcs[ARC_SLOTS];
static size_t s_count, s_children;
static uint64_t s_registry_begin, s_registry_end;
static bool s_checked, s_available;
static void (*s_mesh)(void *);
static bool read_mem(uint64_t address, void *out, size_t size) {
    vm_size_t copied=0;
    return address && vm_read_overwrite(mach_task_self(),address,size,(vm_address_t)out,&copied)==KERN_SUCCESS && copied==size;
}
static uint64_t read64(uint64_t address) { uint64_t v=0; read_mem(address,&v,8); return v; }
static bool code_pointer(uint64_t p) { uint64_t b=xrc_image_base(); return p>=b && p<b+0x1300000; }
static void *callable(uint64_t p) {
    void *result=(void *)p;
#if __has_feature(ptrauth_calls)
    result=ptrauth_sign_unauthenticated(result,ptrauth_key_function_pointer,0);
#endif
    return result;
}
bool xrc_arc_flow_available(void) {
    if (!s_checked) {
        const unsigned char expected[]={0xe9,0x23,0xb9,0x6d,0xfc,0x6f,0x01,0xa9};
        unsigned char actual[sizeof(expected)];
        uint64_t p=xrc_image_base()+XRC_OFF_ARC_FLOW_MESH;
        s_available=read_mem(p,actual,sizeof(actual)) && !memcmp(actual,expected,sizeof(actual));
        s_mesh=(void (*)(void *))callable(p); s_checked=true;
        xrc_logi(XRCLC_BOOT,@"practice-native-flow v2: canonical Arc geometry available=%d",s_available);
    }
    return s_available;
}
void xrc_arc_flow_reset(void) {
    for (size_t i=0;i<s_count;++i) free(s_arcs[i].segments);
    memset(s_arcs,0,sizeof(s_arcs)); s_count=s_children=0;
    s_registry_begin=s_registry_end=0;
}
static bool children(uint64_t render, uint64_t *begin, uint64_t *end) {
    uint64_t parent=read64(render+0x278), vt=read64(parent), getter=read64(vt+0x220);
    uint32_t insns[2]={0};
    // getChildren must be a simple pointer getter, not an arbitrary virtual call.
    if (!code_pointer(getter) || !read_mem(getter,insns,sizeof(insns)) || insns[1]!=0xd65f03c0 ||
        ((insns[0]&0xffc003ff)!=0x91000000 && (insns[0]&0xffc003ff)!=0xf9400000)) return false;
    uint64_t list=((uint64_t (*)(void *))callable(getter))((void *)parent);
    *begin=read64(list); *end=read64(list+8);
    return *begin && *end>*begin && (*end-*begin)%8==0 && (*end-*begin)/8<=8192;
}
static void capture(uint64_t render) {
    uint64_t logic=read64(render+0x268);
    if (read64(logic)!=xrc_image_base()+XRC_LN_VPTR_ARC) return;
    uint64_t begin=0,end=0; int32_t times[2];
    if (!children(render,&begin,&end) || !read_mem(logic+24,times,sizeof(times))) return;
    arc_t *arc=NULL;
    for (size_t i=0;i<s_count;++i) if (s_arcs[i].render==render) { arc=&s_arcs[i]; break; }
    if (arc && arc->segments && arc->logic==logic && arc->begin==begin && arc->end==end &&
        arc->start_ms==times[0] && arc->end_ms==times[1]) { arc->live=true; return; }
    if (!arc) { if (s_count==ARC_SLOTS) return; arc=&s_arcs[s_count++]; }
    s_children-=arc->count; free(arc->segments); memset(arc,0,sizeof(*arc));
    arc->render=render; arc->logic=logic; arc->begin=begin; arc->end=end;
    arc->start_ms=times[0]; arc->end_ms=times[1];
    size_t count=(end-begin)/8;
    if (count>ARC_CHILD_LIMIT-s_children) return;
    segment_t *segments=calloc(count,sizeof(*segments)); if (!segments) return;
    for (size_t i=0;i<count;++i) {
        segment_t *s=&segments[i]; s->node=read64(begin+i*8); s->vtable=read64(s->node);
        uint8_t visible=0;
        if (!s->vtable || !read_mem(s->node+0x2b4,s->original,sizeof(s->original)) ||
            !read_mem(s->node+0x1c1,&visible,1)) { free(segments); return; }
        for (size_t j=0;j<24;++j) if (!isfinite(s->original[j])) { free(segments); return; }
        s->visible=visible!=0;
    }
    *arc=(arc_t){render,logic,begin,end,times[0],times[1],segments,count,1.0,true}; s_children+=count;
}
void xrc_arc_flow_frame(void *scene,double factor,int chart_ms) {
    if (![NSThread isMainThread] || !scene || !isfinite(factor) || factor<=0 || !xrc_arc_flow_available()) return;
    uint64_t manager=read64((uint64_t)scene+880);
    uint64_t begin=read64(manager+0x378),end=read64(manager+0x380);
    if (!begin || end<begin || (end-begin)%8 || (end-begin)/8>65536) return;
    if (begin!=s_registry_begin || end!=s_registry_end) {
        for (size_t i=0;i<s_count;++i) s_arcs[i].live=false;
        for (uint64_t p=begin;p<end;p+=8) capture(read64(p));
        s_registry_begin=begin; s_registry_end=end;
        xrc_logd(XRCLC_BOOT,@"[flow-arc] snapshots=%zu segments=%zu",s_count,s_children);
    }
    for (size_t i=0;i<s_count;++i) {
        arc_t *arc=&s_arcs[i];
        if (!arc->live || !arc->segments || chart_ms>arc->end_ms) continue;
        if (arc->factor==factor && (factor==1 || chart_ms<arc->start_ms)) continue;
        if (read64(arc->render+0x268)!=arc->logic ||
            read64(arc->logic)!=xrc_image_base()+XRC_LN_VPTR_ARC) continue;
        uint64_t cb=0,ce=0;
        if (!children(arc->render,&cb,&ce)) continue;
        if (cb!=arc->begin || ce!=arc->end) { capture(arc->render); continue; }
        // Future arcs need work only on factor change. Active arcs must undo the
        // previous frame's clipping before the native renderer clips again.
        for (size_t j=0;j<arc->count;++j) {
            segment_t *s=&arc->segments[j];
            if (read64(cb+j*8)!=s->node || read64(s->node)!=s->vtable) continue;
            float target[24],current[24];
            xrc_arc_flow_geometry(target,s->original,factor);
            if (!read_mem(s->node+0x2b4,current,sizeof(current))) continue;
            if (memcmp(current,target,sizeof(target))) {
                memcpy((void *)(s->node+0x2b4),target,sizeof(target));
                s_mesh((void *)s->node); // updates native vertex buffers, not node scale
            }
            if (s->visible && !*(uint8_t *)(s->node+0x1c1)) {
                *(uint8_t *)(s->node+0x1c1)=1;
                *(uint32_t *)(s->node+0x130)|=0x31;
            }
        }
        arc->factor=factor;
    }
}
