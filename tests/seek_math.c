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
    return 0;
}
