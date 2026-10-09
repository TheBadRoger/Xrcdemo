#pragma once
#include <cmath>
#include "signalsmith-stretch/signalsmith-stretch.h"

// FMOD owns the source clock and resampling; this spectral stretcher restores
// pitch in its fixed-size mixing blocks without changing that clock.
class XRCStretch {
    signalsmith::stretch::SignalsmithStretch<float> engine{0};
    int channels;
    struct Input {
        const float *data; int channels;
        struct Channel { const float *data; int stride;
            float operator[](int i) const { return data[i*stride]; }
        };
        Channel operator[](int c) const { return {data+c,channels}; }
    };
    struct Output {
        float *data; int channels;
        struct Channel { float *data; int stride;
            float &operator[](int i) const { return data[i*stride]; }
        };
        Channel operator[](int c) const { return {data+c,channels}; }
    };
public:
    XRCStretch(int channels,int sampleRate):channels(channels) {
        engine.presetDefault(channels,float(sampleRate),true);
    }
    int latencySamples() const { return engine.inputLatency()+engine.outputLatency(); }
    void reset() { engine.reset(); }
    void process(const float *input,float *output,int frames,double rate) {
        if (!std::isfinite(rate) || rate<0.05 || rate>4.0) rate=1.0;
        engine.setTransposeFactor(float(1.0/rate));
        engine.process(Input{input,channels},frames,Output{output,channels},frames);
    }
};
