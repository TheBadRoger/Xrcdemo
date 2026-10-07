#pragma once
#include <stdbool.h>
#include <stdint.h>

void xrc_konzetsu_configure(int id, bool effects, bool challenge_gauge);
bool xrc_konzetsu_available(void);
uint32_t xrc_konzetsu_round_options(void);
void xrc_konzetsu_tick(void);

// BRK callbacks: atomics/register changes only; no allocation or logging.
void xrc_konzetsu_chart(void *context);
void xrc_konzetsu_id(void *context);
void xrc_konzetsu_active(void *context);
void xrc_konzetsu_score(void *context);
void xrc_konzetsu_hpbar(void *context);
void xrc_konzetsu_info(void *context);
