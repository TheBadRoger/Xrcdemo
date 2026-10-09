#include <cassert>
#include <vector>
#include <atomic>
#include <cstdlib>
#include <new>
#include "XRCStretch.h"
#include "../gameplay/XRCAudioStretch.mm"

static bool trackAllocations=false;
static unsigned allocations=0;
void *operator new(std::size_t size) {
    if (trackAllocations) ++allocations;
    if (void *p=std::malloc(size)) return p;
    throw std::bad_alloc();
}
void operator delete(void *p) noexcept { std::free(p); }
void operator delete(void *p,std::size_t) noexcept { std::free(p); }

static DSPDescription callbacks;
static int32_t fakeCreate(uint64_t,DSPDescription *description,void **dsp) {
    callbacks=*description; *dsp=&callbacks; return 0;
}
extern "C" uint64_t xrc_image_base(void) {
    return reinterpret_cast<uint64_t>(&fakeCreate)-XRC_OFF_FMOD_CREATE_DSP;
}
static int32_t fakeSampleRate(DSPState *,int *rate) { *rate=44100; return 0; }
static int32_t fakeBlockSize(DSPState *,unsigned *size) { *size=512; return 0; }

int main() {
    constexpr int sampleRate=48000,frames=127;
    const double pi=std::acos(-1.0);
    std::vector<float> input(frames*2),output(frames*2);
    XRCStretch stretch(2,sampleRate);
    assert(stretch.latencySamples()>0);
    for (double rate : {0.5,0.75,1.0,1.25,1.5,2.0}) {
        stretch.reset();
        int crossings=0,count=0;
        double energy=0,stereoError=0;
        float previous=0;
        for (int block=0;block<800;++block) {
            for (int i=0;i<frames;++i) {
                input[i*2]=float(0.25*std::sin(2*pi*440*rate*(block*frames+i)/sampleRate));
                input[i*2+1]=-input[i*2];
            }
            stretch.process(input.data(),output.data(),frames,rate);
            if (block<150) continue;
            for (int i=0;i<frames;++i) {
                float v=output[i*2];
                assert(std::isfinite(v) && std::isfinite(output[i*2+1]));
                if (previous<=0 && v>0) ++crossings;
                previous=v; ++count;
                energy+=v*v;
                stereoError+=std::pow(v+output[i*2+1],2);
            }
        }
        double frequency=double(crossings)*sampleRate/count;
        assert(std::abs(frequency-440)<5);
        assert(energy/count>0.005 && energy/count<0.1);
        assert(stereoError/count<1e-6);
        // A seek must erase both input history and queued output immediately.
        stretch.reset();
        std::fill(input.begin(),input.end(),0);
        for (int block=0;block<150;++block) {
            stretch.process(input.data(),output.data(),frames,rate);
            for (float sample : output) assert(std::abs(sample)<1e-7);
        }
    }
    // Changing rate without a seek remains finite and preserves fixed latency.
    int latency=stretch.latencySamples();
    for (int block=0;block<100;++block) {
        double rate=block%2 ? 0.6 : 1.5;
        for (int i=0;i<frames*2;++i) input[i]=float(0.2*std::sin(i+block*frames));
        stretch.process(input.data(),output.data(),frames,rate);
        assert(stretch.latencySamples()==latency);
        for (float v : output) assert(std::isfinite(v));
    }
    // Exercise the actual FMOD bridge, including its deferred reset and ABI.
    void *dsp=nullptr;
    assert(xrc_stretch_create(1,&dsp)==0 && dsp);
    DSPFunctions functions={}; functions.sampleRate=fakeSampleRate;
    functions.blockSize=fakeBlockSize;
    DSPState state={}; state.functions=&functions;
    assert(callbacks.create(&state)==0);
    XRCStretch reference(2,44100);
    assert(std::abs(xrc_stretch_latency_ms()-1000.0*reference.latencySamples()/44100)<1e-6);
    xrc_stretch_set_rate(0.6);
    int outChannels=2;
    trackAllocations=true;
    for (int block=0;block<100;++block)
        assert(callbacks.read(&state,input.data(),output.data(),frames,2,&outChannels)==0);
    // FMOD may reuse the same buffer for input and output.
    assert(callbacks.read(&state,input.data(),input.data(),frames,2,&outChannels)==0);
    xrc_stretch_reset();
    std::fill(input.begin(),input.end(),0);
    assert(callbacks.read(&state,input.data(),output.data(),frames,2,&outChannels)==0);
    for (float v : output) assert(std::abs(v)<1e-7);
    // Channel layout changes also discard stereo history before mono playback.
    assert(callbacks.read(&state,input.data(),output.data(),frames,1,&outChannels)==0);
    assert(outChannels==1);
    assert(callbacks.read(&state,input.data(),output.data(),frames,6,&outChannels)!=0);
    trackAllocations=false;
    assert(allocations==0);
    assert(callbacks.release(&state)==0 && !state.data);
    return 0;
}
