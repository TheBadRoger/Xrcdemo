# Vendored Signalsmith audio processing

Unmodified headers, pinned to:

- Stretch 1.3.2: https://github.com/Signalsmith-Audio/signalsmith-stretch/commit/a670068d9aeb64913331d5cc29337b19a457a7df
- Linear: https://github.com/Signalsmith-Audio/linear/commit/146b26f91b48835d665fa0498d64d9617818d27a

Only the headers needed by the portable and Apple Accelerate backends are included.
Both components use the MIT license; full texts are in their respective directories.
Build with C++17. The iOS target uses `SIGNALSMITH_USE_ACCELERATE` and links Accelerate.
