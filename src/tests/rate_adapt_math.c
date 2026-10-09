#include <assert.h>
#include "XRCRateMath.h"
int main(void) {
    const double rates[] = {0.25, 0.5, 0.75, 1, 2, 4};
    for (unsigned i=0; i<sizeof(rates)/sizeof(rates[0]); ++i) {
        double r=rates[i];
        assert(fabs(xrc_adapt_flow_factor(r,true)*r-1)<1e-8);
        assert(fabs((100+xrc_adapt_offset_extra(100,r,true))/r-100)<1e-8);
        assert(fabs((-100+xrc_adapt_offset_extra(-100,r,true))/r+100)<1e-8);
        assert(xrc_adapt_offset_extra(100,r,false)==0);
    }
    int32_t base=147, old=0;
    for (int i=0;i<100;++i) {
        int32_t next=xrc_adapt_offset_extra(100,rates[i%6],true);
        base=xrc_adapt_add(base,(int64_t)next-old); old=next;
        assert(base-old==147);
        // Seek calibration strips the adaptive term before adding DSP delay.
        int chart_minus_audio=42-old-20;
        assert(chart_minus_audio+old+20==42);
    }
    assert(xrc_adapt_add(base,-old)==147);
    assert(xrc_adapt_flow_factor(NAN,true)==1);
    assert(xrc_adapt_add(INT_MAX,100)==INT_MAX);
    uint64_t units = 0;
    assert(xrc_live_flow_units(214748364.7,&units));
    assert(units==2147483647ULL);
    assert(xrc_live_flow_units(0.1,&units) && units==1);
    assert(xrc_live_flow_units(8.04,&units) && units==80);
    assert(!xrc_live_flow_units(214748364.8,&units));
    assert(!xrc_live_flow_units(2147483647.0,&units));
    assert(!xrc_live_flow_units(INFINITY,&units));
    assert(!xrc_live_flow_units(NAN,&units));
    assert(!xrc_live_flow_units(0,&units));
    assert(!xrc_live_flow_units(-1,&units));
    assert(xrc_flow_value(50,0.5,true)==100);
    assert(xrc_flow_value(50,2,true)==25);
    assert(xrc_flow_value(50,0.75,true)==67);
    assert(xrc_flow_value(50,0.5,false)==50);
    assert(xrc_flow_value(INT_MAX,0.05,true)==INT_MAX);
    int original=50, locked=xrc_flow_value(original,0.5,true);
    for (int incoming=1;incoming<=200;++incoming) {
        assert(xrc_flow_lock_write(incoming,locked,true)==100);
        assert(xrc_flow_lock_write(incoming,locked,false)==incoming);
    }
    assert(xrc_flow_lock_write(original,locked,false)==50); // unlock restores saved original
    assert(xrc_flow_lock_write(70,0,true)==70); // initialization cannot force a zero value
    return 0;
}
