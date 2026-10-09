#include "XRCSeekMath.h"
#include <assert.h>

int main(void) {
    // Calibration survives repeated forward/backward seeks, including DSP offset.
    const int offsets[] = {-180, -40, 0, 25, 120};
    const unsigned targets[] = {0, 100, 1000, 45000, 62000};
    for (unsigned i=0; i<5; ++i)
        for (unsigned j=0; j<5; ++j)
            assert((int64_t)xrc_seek_chart_target(targets[j], offsets[i]) - targets[j] == offsets[i]);
    assert(xrc_seek_chart_target(INT_MAX, 50) == INT_MAX);
    assert(xrc_seek_chart_target(0, INT_MIN) == INT_MIN);
    assert(!xrc_seek_landed(62000, 45000, 16000, 1.0)); // stale pre-seek position
    assert(!xrc_seek_landed(3000, 45000, 16000, 1.0)); // failed forward seek
    assert(xrc_seek_landed(45000, 45000, 0, 1.0)); // paused channel acknowledges target
    assert(xrc_seek_landed(45032, 45000, 16000, 2.0)); // playing at 2x
    assert(xrc_seek_landed(45008, 45000, 16000, 0.5));
    assert(!xrc_seek_landed(44900, 45100, 16000, 1.0));
    // DSP delay is converted from real ms separately at each playback speed.
    assert(xrc_seek_output_delay(1.0, 96.0) == 96);
    assert(xrc_seek_output_delay(0.75, 96.0) == 72);
    assert(xrc_seek_output_delay(0.6, 96.0) == 58);
    assert(xrc_seek_output_delay(0.5, 96.0) == 48);
    assert(xrc_seek_output_delay(0.25, 96.0) == 24);
    assert(xrc_seek_output_delay(0.0, 96.0) == 0);
    assert(xrc_seek_output_delay(1.0, 0.0) == 0);
    // A rate change retains the source position. Shift chart base by only the
    // difference in delay, including restoring 1x and repeated rate changes.
    int source=20000,chart=source-xrc_seek_output_delay(0.6,150);
    double previousRate=0.6;
    const double changes[]={1.5,0.75,1.0,2.0,0.6,1.0};
    for (unsigned i=0;i<sizeof(changes)/sizeof(changes[0]);++i) {
        int delta=xrc_seek_output_delay(changes[i],150)-xrc_seek_output_delay(previousRate,150);
        chart-=delta;
        assert(chart==source-xrc_seek_output_delay(changes[i],150));
        previousRate=changes[i];
    }
    const int calibration = 20;
    assert(xrc_seek_calibrated_offset(calibration, 96) == -76);
    assert(xrc_seek_calibrated_offset(calibration, 48) == -28);
    assert(xrc_seek_calibrated_offset(calibration, 24) == -4);
    assert(xrc_seek_calibrated_offset(INT_MIN, 96) == INT_MIN);
    assert(!xrc_seek_audio_needs_compensation(1000,45000,100,200,false));
    assert(!xrc_seek_audio_needs_compensation(1000,45000,300,200,true));
    assert(xrc_seek_audio_needs_compensation(1000,45000,300,200,false));
    assert(!xrc_seek_audio_needs_compensation(UINT32_MAX,UINT32_MAX,300,200,false));
    assert(xrc_seek_runtime_offset(20,48,-50)==22);
    assert(xrc_seek_runtime_offset(INT_MAX,INT_MAX,-7)==7);
    assert(xrc_seek_runtime_offset(INT_MIN,INT_MAX,INT_MAX)==INT_MIN);
    xrc_sync_samples_t samples={0}; int32_t result=12345;
    for (unsigned i=0;i<7;++i)
        assert(!xrc_seek_sample_calibration(&samples,(int32_t)(i*100),i*50000,&result));
    assert(result==12345); // unstable loading samples cannot seed calibration
    for (unsigned i=0;i<6;++i)
        assert(!xrc_seek_sample_calibration(&samples,20,400000+i*50000,&result));
    assert(xrc_seek_sample_calibration(&samples,22,700000,&result) && result==20);
    samples=(xrc_sync_samples_t){0};
    for (unsigned i=0;i<7;++i)
        assert(!xrc_seek_sample_calibration(&samples,20,i*20000,&result));
    assert(xrc_seek_sample_calibration(&samples,20,200000,&result));
    return 0;
}
