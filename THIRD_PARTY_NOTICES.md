# 第三方与上游组件声明

本仓库包含的第三方与上游组件如下，各部分依其原始许可提供。本文件作为这些许可
所要求的版权声明与许可全文的汇集处（单份副本另随附于各组件目录）。

## 1. AccDemo — 时基/变速与早期结构的来源

- 项目：https://github.com/brendonjkding/AccDemo
- 说明：本项目早期版本由该项目（Arcaea 适配）衍生而来；现版本中的速度控制/时钟
  缩放模块与部分配置结构（如 `speedKeys` 等键位）仍然衍生自它。
- 许可：MIT License，Copyright (c) 2020 brendonjkding

## 2. WHToast — toast UI 库（`src/vendor/WHToast/`）

- 项目：https://github.com/remember17/WHToast
- 许可：MIT License，Copyright (c) 2018 wuhao
  （单份副本：`src/vendor/WHToast/LICENSE`）

## 3. fishhook — 符号重绑定库（`src/vendor/fishhook/`）

- 项目：https://github.com/facebook/fishhook
- 许可：BSD 3-Clause License，Copyright (c) 2013, Facebook, Inc.
  （许可全文亦随源码文件 `src/vendor/fishhook/fishhook.h` 头部提供）

## 4. Signalsmith Stretch / Linear — 实时音乐频谱处理

- 项目：https://github.com/Signalsmith-Audio/signalsmith-stretch 和 https://github.com/Signalsmith-Audio/linear
- 许可：MIT，Copyright (c) Geraint Luff / Signalsmith Audio；完整声明见组件 LICENSE.txt。
- 固定源码版本及构建后端：`src/vendor/signalsmith-stretch/README.md`。
- 许可全文：`src/vendor/signalsmith-stretch/LICENSE.txt`、`src/vendor/signalsmith-stretch/signalsmith-linear/LICENSE.txt`。

---

## MIT License（适用于上述 AccDemo 与 WHToast）

Copyright (c) 2020 brendonjkding (AccDemo)
Copyright (c) 2018 wuhao (WHToast)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## BSD 3-Clause License（适用于 fishhook）

Copyright (c) 2013, Facebook, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.
  * Neither the name Facebook nor the names of its contributors may be used to
    endorse or promote products derived from this software without specific
    prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
