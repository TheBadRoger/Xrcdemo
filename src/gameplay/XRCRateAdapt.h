#pragma once
#include <stdbool.h>
#include <stdint.h>

void xrc_rate_adapt_install(void);
void xrc_rate_adapt_set_enabled(bool enabled);
bool xrc_rate_adapt_enabled(void);
bool xrc_rate_adapt_available(void);
bool xrc_rate_adapt_set_native_flow(double speed); // writes the native setting only while unlocked
double xrc_rate_adapt_native_flow(void);
void xrc_rate_adapt_native_tick(void);
void xrc_rate_adapt_frame_begin(void *scene, void *note_group);
int32_t xrc_rate_adapt_offset_extra(void *note_group);
void xrc_rate_adapt_preference_write(void *context);
