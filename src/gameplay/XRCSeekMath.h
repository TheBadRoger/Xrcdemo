#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <limits.h>

// Targets originate in the audio timeline. Preserve chart - audio, including calibration.
static inline int32_t xrc_seek_chart_target(uint32_t audio, int32_t offset) {
    int64_t value = (int64_t)audio + offset;
    return value > INT_MAX ? INT_MAX : value < INT_MIN ? INT_MIN : (int32_t)value;
}
static inline bool xrc_seek_landed(uint32_t audio, uint32_t target,
                                   uint64_t elapsed_us, double rate) {
    // A playing channel advances while the asynchronous seek is being acknowledged.
    int64_t delta = (int64_t)audio - target;
    if (rate==0) return delta>=-2 && delta<=2;
    double advance = (double)elapsed_us / 1000.0 * rate;
    return delta >= -150 && (double)delta <= advance + 150.0;
}

// Convert real output latency to audio/chart milliseconds at the current playback rate.
static inline int32_t xrc_seek_output_delay(double rate, double latency_ms) {
    if (!(rate > 0.0) || !(latency_ms > 0.0) || rate > 4.0 || latency_ms > 5000.0) return 0;
    return (int32_t)(rate * latency_ms + 0.5);
}
static inline int32_t xrc_seek_calibrated_offset(int32_t calibration, int32_t delay) {
    int64_t value = (int64_t)calibration - delay;
    return value > INT_MAX ? INT_MAX : value < INT_MIN ? INT_MIN : (int32_t)value;
}

// A plugin seek owns its DSP alignment. Do not turn its position retreat into
// another Channel::setPosition after the transaction has completed.
static inline bool xrc_seek_audio_needs_compensation(uint32_t position,uint32_t previous,
                                                     uint64_t now,uint64_t owned_until,bool seeking) {
    return !seeking && now>=owned_until && (uint64_t)position+500<previous;
}
static inline int32_t xrc_seek_runtime_offset(int32_t calibration,int32_t delay,int32_t extra) {
    int64_t value=(int64_t)calibration-delay-extra;
    return value>INT_MAX ? INT_MAX : value<INT_MIN ? INT_MIN : (int32_t)value;
}
#define XRC_SYNC_SAMPLES 7
typedef struct { int32_t values[XRC_SYNC_SAMPLES]; unsigned count,cursor; uint64_t started; } xrc_sync_samples_t;
static inline bool xrc_seek_sample_calibration(xrc_sync_samples_t *samples,int32_t value,uint64_t now,int32_t *result) {
    if (!samples->count) samples->started=now;
    samples->values[samples->cursor++%XRC_SYNC_SAMPLES]=value;
    if (samples->count<XRC_SYNC_SAMPLES) ++samples->count;
    if (samples->count<XRC_SYNC_SAMPLES || now<samples->started || now-samples->started<200000) return false;
    int32_t sorted[XRC_SYNC_SAMPLES];
    for (unsigned i=0;i<XRC_SYNC_SAMPLES;++i) {
        sorted[i]=samples->values[i];
        for (unsigned j=i;j>0 && sorted[j]<sorted[j-1];--j) {
            int32_t temp=sorted[j]; sorted[j]=sorted[j-1]; sorted[j-1]=temp;
        }
    }
    if ((int64_t)sorted[XRC_SYNC_SAMPLES-1]-sorted[0]>24) return false;
    *result=sorted[XRC_SYNC_SAMPLES/2]; return true;
}

// Only release a pause that we acquired on this exact scene and BGM group.
static inline bool xrc_seek_can_resume(bool owned,uint64_t scene,uint64_t player,uint64_t group,
                                       uint64_t current_scene,uint64_t current_player,uint64_t current_group) {
    return owned && scene && player && group && scene==current_scene &&
        player==current_player && group==current_group;
}

// A native pause or a suspended update loop must not be extrapolated at the rate.
static inline bool xrc_seek_resume_alignment(bool paused_seen,uint64_t gap_us) {
    return paused_seen || gap_us>200000ULL;
}
