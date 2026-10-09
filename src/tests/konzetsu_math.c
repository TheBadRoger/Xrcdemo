#include <assert.h>
#include "XRCKonzetsuMath.h"
int main(void) {
    const int valid[] = {1,2,3,4,6};
    for (int i=0;i<5;i++) assert(xrc_konzetsu_valid_id(valid[i]));
    assert(!xrc_konzetsu_valid_id(0));
    assert(!xrc_konzetsu_valid_id(5));
    assert(!xrc_konzetsu_valid_id(7));
    assert(xrc_konzetsu_native_id(4)==5);
    assert(xrc_konzetsu_native_id(6)==6);
    assert(xrc_konzetsu_native_id(5)==0);
    for (int effects=0;effects<2;effects++) {
        for(int gauge=0;gauge<2;gauge++) {
            uint32_t options=xrc_konzetsu_options(4,effects,gauge);
            assert((options & 0xff)==4);
            assert(xrc_konzetsu_effects(options)==(bool)effects);
            assert(xrc_konzetsu_gauge(options)==(bool)(effects && gauge));
        }
    }
    assert((xrc_konzetsu_options(5,true,true)&0xff)==1);
    xrc_konzetsu_interval_t range;
    assert(xrc_konzetsu_scale_interval((xrc_konzetsu_interval_t){12700,22000},150300,&range));
    assert(range.begin==12700 && range.end==22000);
    assert(xrc_konzetsu_scale_interval((xrc_konzetsu_interval_t){145300,150300},1200000,&range));
    assert(range.begin>0 && range.end==1200000);
    assert(xrc_konzetsu_scale_interval((xrc_konzetsu_interval_t){145300,150300},1000,&range));
    assert(range.end==1000 && range.begin<range.end);
    assert(!xrc_konzetsu_scale_interval((xrc_konzetsu_interval_t){0,100},999,&range));
    assert(!xrc_konzetsu_scale_interval((xrc_konzetsu_interval_t){2,1},150300,&range));
    assert(!xrc_konzetsu_scale_interval((xrc_konzetsu_interval_t){0,150301},150300,&range));
    assert(!xrc_konzetsu_scale_interval((xrc_konzetsu_interval_t){0,100},150300,0));
    return 0;
}
