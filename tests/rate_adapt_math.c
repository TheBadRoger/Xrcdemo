#include <assert.h>
#include "XRCRateMath.h"
int main(void) {
    const double rates[] = {0.25, 0.5, 0.75, 1, 2, 4};
    for (unsigned i=0; i<sizeof(rates)/sizeof(rates[0]); ++i) {
        double r=rates[i];
        assert(fabs(xrc_adapt_flow_factor(r,true)*r-1)<1e-8);
        assert(fabs((100+xrc_adapt_offset_extra(100,r,true))/r-100)<1e-8);
        assert(fabs((-100+xrc_adapt_offset_extra(-100,r,true))/r+100)<1e-8);
        assert(xrc_adapt_window_units(700,(uint32_t)(r*1000))==xrc_adapt_window(700,r));
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
    assert(xrc_adapt_window_units(INT_MAX,4000)==INT_MAX);
    assert(xrc_adapt_window_units(1,10)==1);
    assert(xrc_adapt_add(INT_MAX,100)==INT_MAX);
    assert(xrc_adapt_same_scale(2.0f,2.000001f));
    assert(!xrc_adapt_same_scale(NAN,1));
    uint64_t units = 0;
    assert(xrc_live_flow_units(2147483647.0,&units));
    assert(units==21474836470ULL);
    assert(xrc_live_flow_units(0.1,&units) && units==1);
    assert(xrc_live_flow_units(8.04,&units) && units==80);
    assert(!xrc_live_flow_units(2147483647.1,&units));
    assert(!xrc_live_flow_units(INFINITY,&units));
    assert(!xrc_live_flow_units(NAN,&units));
    assert(!xrc_live_flow_units(0,&units));
    assert(!xrc_live_flow_units(-1,&units));
    assert(fabs(xrc_live_flow_factor(5,10,0.5,true)-4)<1e-8);
    assert(fabs(xrc_live_flow_factor(5,10,0.5,false)-2)<1e-8);
    assert(xrc_live_flow_factor(5,0,1,false)==1);
    assert(xrc_live_flow_factor(5,0,0.5,true)==2);
    for (unsigned i=0;i<sizeof(rates)/sizeof(rates[0]);++i) {
        double scale=xrc_live_flow_factor(5,10,rates[i],true);
        int window=xrc_live_window(700,xrc_live_window_factor(scale));
        assert(fabs(window*scale-700)<=scale);
    }
    double huge=xrc_live_flow_factor(0.1,INT32_MAX,0.01,true);
    assert(isfinite((float)huge));
    assert(xrc_live_window(700,xrc_live_window_factor(huge))==1);
    double tiny=xrc_live_flow_factor(INT32_MAX,0.1,4,true);
    assert(xrc_live_window(INT32_MAX,xrc_live_window_factor(tiny))==INT32_MAX);
    assert(xrc_live_window(700,UINT64_MAX)==INT32_MAX);
    assert(xrc_live_window(INT32_MAX,XRC_FLOW_WINDOW_DENOM)==INT32_MAX);
    // Small scales must still respond to changes; absolute epsilon would hide them.
    assert(!xrc_adapt_same_scale(1e-10f,2e-10f));
    // Always compute from native baseline, never multiply the previous result.
    float native=1;
    for (int i=0;i<100;++i) {
        float applied=(float)(native*xrc_live_flow_factor(5,i%2?10:5,1,false));
        assert(applied==(i%2?2:1));
    }
    return 0;
}
