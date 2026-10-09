#pragma once
#include <stdbool.h>
#include <stdint.h>

void xrc_rate_adapt_install(void);
void xrc_rate_adapt_set_offset(bool enabled);
void xrc_rate_adapt_set_flow(bool enabled);
bool xrc_rate_adapt_offset_enabled(void);
bool xrc_rate_adapt_flow_enabled(void);
bool xrc_rate_adapt_flow_available(void);
bool xrc_rate_adapt_set_native_flow(double speed); // writes the shared native value
double xrc_rate_adapt_native_flow(void);
void xrc_rate_adapt_native_tick(void);
void xrc_rate_adapt_frame_begin(void *scene, void *note_group);
int32_t xrc_rate_adapt_offset_extra(void *note_group);
void xrc_rate_adapt_preference_write(void *context);
