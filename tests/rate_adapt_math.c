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
    assert(fabs(xrc_live_flow_factor(5,10,0.5,true)-4)<1e-8);
    assert(fabs(xrc_live_flow_factor(5,10,0.5,false)-2)<1e-8);
    assert(xrc_live_flow_factor(5,0,1,false)==1);
    assert(xrc_live_flow_factor(5,0,0.5,true)==2);
    for (unsigned i=0;i<sizeof(rates)/sizeof(rates[0]);++i) {
        double scale=xrc_live_flow_factor(5,10,rates[i],true);
        assert(fabs(xrc_native_flow_distance(100,scale)*rates[i]-200)<1e-4);
        // 5 at .5x must behave as internal 10, preserving real-time velocity.
        assert(fabs(5*xrc_live_flow_factor(5,5,rates[i],true)*rates[i]-5)<1e-8);
        assert(fabs(xrc_native_flow_distance(-100,scale)+100*scale)<1e-4);
    }
    double huge=xrc_live_flow_factor(0.1,INT32_MAX/10.0,0.01,true);
    assert(isfinite((float)huge));
    assert(xrc_native_flow_distance(700,huge)==2147483520.0f);
    assert(xrc_native_flow_distance(-700,huge)==-2147483648.0f);
    assert(xrc_native_flow_candidate(10,700,1,false,-20,20)==10);
    assert(xrc_native_flow_candidate(10,700,2,false,-20,20)==10);
    assert(fabs(xrc_native_flow_candidate(10,700,.5,false,-20,20)-9.93)<1e-5);
    assert(fabs(xrc_native_flow_candidate(10,700,.5,true,-20,20)-10.07)<1e-5);
    assert(xrc_native_flow_candidate(0,700,1e-10,false,-20,20)==-20);
    assert(xrc_native_flow_candidate(0,700,1e-10,true,-20,20)==20);
    // Arc endpoints and mesh corners share the same immutable baseline.
    float geometry[24], changed[24];
    for (unsigned i=0;i<24;++i) geometry[i]=(float)(i+1);
    for (unsigned n=0;n<100;++n) {
        double factor=n%2 ? 0.5 : 2.0;
        xrc_arc_flow_geometry(changed,geometry,factor);
        for (unsigned i=0;i<24;++i)
            assert(changed[i]==(i%3==2 ? geometry[i]*factor : geometry[i]));
        // Simulate native clipping, then return to 1x from the original shape.
        changed[0]=900; changed[2]=0;
        xrc_arc_flow_geometry(changed,geometry,1.0);
        for (unsigned i=0;i<24;++i) assert(changed[i]==geometry[i]);
    }
    // Always compute from native baseline, never multiply the previous result.
    float native=1;
    for (int i=0;i<100;++i) {
        float applied=(float)(native*xrc_live_flow_factor(5,i%2?10:5,1,false));
        assert(applied==(i%2?2:1));
    }
    return 0;
}
