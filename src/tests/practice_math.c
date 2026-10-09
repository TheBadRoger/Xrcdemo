#include "XRCPracticeMath.h"
#include <assert.h>

int main(void) {
    const int th[4] = {25, 50, 100, 120};
    assert(xrc_practice_grade(24, th, 1, true) == 0);
    assert(xrc_practice_grade(25, th, 1, true) == 1);
    assert(xrc_practice_grade(50, th, 1, true) == 2);
    assert(xrc_practice_grade(100, th, 1, true) == 3);
    assert(xrc_practice_grade(120, th, 1, true) == 3);
    assert(xrc_practice_grade(121, th, 1, true) == -1);
    assert(xrc_practice_grade(12, th, 0.5, true) == 0);
    assert(xrc_practice_grade(13, th, 0.5, true) == 1);
    assert(xrc_practice_grade(49, th, 2, true) == 0);
    assert(xrc_practice_grade(50, th, 2, true) == 1);
    assert(xrc_practice_grade(60, th, 0.5, true) == 3);
    assert(xrc_practice_grade(61, th, 0.5, true) == -1);
    assert(xrc_practice_grade(60, th, 0.5, false) == 2);
    assert(xrc_practice_grade(60, th, 2, false) == 2);
    assert(xrc_practice_grade(25, th, NAN, true) == 1);
    assert(xrc_practice_rate(INFINITY) == 1);
    assert(xrc_practice_bound(INT32_MAX - 2, 7) == INT32_MAX);
    assert(xrc_practice_bound(INT32_MIN + 2, -7) == INT32_MIN);
    assert(xrc_practice_bound(1000, ceil(100 * 0.5)) == 1050);
    assert(xrc_practice_bound(1000, -ceil(120 * 2.0)) == 760);
    int32_t units;
    assert(xrc_practice_flow_units(0.1, &units) && units == 1);
    assert(xrc_practice_flow_units(6.6, &units) && units == 66);
    assert(xrc_practice_flow_units(15.0, &units) && units == 150);
    assert(!xrc_practice_flow_units(0.099, &units));
    assert(!xrc_practice_flow_units(-1, &units));
    assert(!xrc_practice_flow_units(NAN, &units));
    assert(!xrc_practice_flow_units(INFINITY, &units));
    assert(!xrc_practice_flow_units((double)INT32_MAX, &units));
    return 0;
}
