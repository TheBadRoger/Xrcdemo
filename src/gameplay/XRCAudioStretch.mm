#include "XRCAudioStretch.h"
#include "XRCStretch.h"
#include "XRCProfile.h"
#include <atomic>
#include <cstddef>
#include <cstring>

extern "C" uint64_t xrc_image_base(void);

// FMOD 2.x DSP ABI, verified against the official fmod_dsp.cs definitions.
// Only callbacks used here have callable types; the remaining slots are null.
struct DSPState;
using Callback=int32_t (*)(DSPState *);
using Read=int32_t (*)(DSPState *,float *,float *,unsigned,int,int *);
struct DSPFunctions {
    void *alloc,*realloc,*free;
    int32_t (*sampleRate)(DSPState *,int *);
    int32_t (*blockSize)(DSPState *,unsigned *);
};
struct DSPState {
    void *instance,*data;
    uint32_t channelMask; int speakerMode;
    float *sidechain; int sidechainChannels;
    DSPFunctions *functions; int system;
};
struct DSPDescription {
    uint32_t sdk; char name[32]; uint32_t version;
    int inputs,outputs;
    Callback create,release,reset;
    Read read;
    void *process,*position;
    int parameters; void *parameterDescriptions;
    void *setFloat,*setInt,*setBool,*setData;
    void *getFloat,*getInt,*getBool,*getData;
    void *shouldProcess,*userdata,*systemRegister,*systemDeregister,*systemMix;
};
static_assert(sizeof(DSPDescription)==0xd8,"FMOD DSP description ABI");
static_assert(offsetof(DSPState,functions)==0x28,"FMOD DSP state ABI");

static std::atomic<double> requestedRate{1.0},latencyMs{0.0};
static std::atomic<unsigned> resetGeneration{0};
struct Processor {
    XRCStretch mono,stereo;
    std::vector<float> inputCopy;
    unsigned generation;
    int channels=0;
    Processor(int sampleRate,unsigned blockSize):mono(1,sampleRate),stereo(2,sampleRate),inputCopy(blockSize*2),
        generation(resetGeneration.load()) {
        latencyMs.store(1000.0*stereo.latencySamples()/sampleRate);
    }
};
static int32_t create(DSPState *state) {
    int sampleRate=0;
    unsigned blockSize=0;
    if (!state || !state->functions || !state->functions->sampleRate ||
        !state->functions->blockSize || state->functions->sampleRate(state,&sampleRate)!=0 ||
        state->functions->blockSize(state,&blockSize)!=0 || sampleRate<8000 || sampleRate>192000 ||
        !blockSize || blockSize>65536) return 31;
    try { state->data=new Processor(sampleRate,blockSize); }
    catch (...) { return 31; }
    return 0;
}
static int32_t release(DSPState *state) {
    delete static_cast<Processor *>(state->data); state->data=nullptr;
    return 0;
}
static int32_t reset(DSPState *state) {
    auto *p=static_cast<Processor *>(state->data);
    if (p) { p->mono.reset(); p->stereo.reset(); p->generation=resetGeneration.load(); }
    return 0;
}
static int32_t read(DSPState *state,float *input,float *output,unsigned frames,int channels,int *outChannels) {
    auto *p=static_cast<Processor *>(state->data);
    if (!p || !input || !output || !outChannels || frames>p->inputCopy.size()/2 || (channels!=1 && channels!=2)) return 31;
    *outChannels=channels;
    unsigned generation=resetGeneration.load();
    if (generation!=p->generation || channels!=p->channels) {
        p->mono.reset(); p->stereo.reset();
        p->generation=generation; p->channels=channels;
    }
    // Allocation/configuration happens at creation, never in the mixer callback.
    if (input==output) {
        std::memcpy(p->inputCopy.data(),input,frames*channels*sizeof(float));
        input=p->inputCopy.data();
    }
    (channels==1 ? p->mono : p->stereo).process(input,output,int(frames),requestedRate.load());
    return 0;
}
int32_t xrc_stretch_create(uint64_t system,void **dsp) {
    static DSPDescription description={};
    description.sdk=110;
    std::strcpy(description.name,"Arc-Practice Stretch");
    description.version=0x10000;
    description.inputs=description.outputs=1;
    description.create=create; description.release=release;
    description.reset=reset; description.read=read;
    auto fn=reinterpret_cast<int32_t (*)(uint64_t,DSPDescription *,void **)>(
        xrc_image_base()+XRC_OFF_FMOD_CREATE_DSP);
    return fn(system,&description,dsp);
}
void xrc_stretch_set_rate(double rate) { requestedRate.store(rate); }
void xrc_stretch_reset(void) { resetGeneration.fetch_add(1); }
double xrc_stretch_latency_ms(void) { return latencyMs.load(); }
