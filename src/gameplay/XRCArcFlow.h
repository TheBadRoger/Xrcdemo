#pragma once
#include <stdbool.h>
void xrc_arc_flow_reset(void);
bool xrc_arc_flow_available(void);
void xrc_arc_flow_frame(void *scene, double factor, int chart_ms);
void xrc_arc_flow_prepare_seek(void);
