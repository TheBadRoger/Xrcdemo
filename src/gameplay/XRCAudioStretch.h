#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
int32_t xrc_stretch_create(uint64_t system,void **dsp);
void xrc_stretch_set_rate(double rate);
void xrc_stretch_reset(void);
double xrc_stretch_latency_ms(void);
#ifdef __cplusplus
}
#endif
