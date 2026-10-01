// © 雾月星辰 & MLXC · github@XingChenRS
// XRCVersion.h — 版本与构建标识（单一来源）。
//
// 用法：
//   · 面板/悬浮球/启动日志统一取 XRC_BUILD_STAMP 与 XRC_VERSION；
//   · 构建戳由 CI 生成 xrc_build_stamp.h（commit sha + 时间）注入，本地构建回退 "dev"。
//     UI 上常显它是为了在设备上肉眼确认当前加载的是哪一版 —— iOS 对已签名二进制有
//     缓存，换了 dylib 重启一两次看不到变化是常事，光看行为会误判成"没生效"。
#pragma once

#if __has_include("xrc_build_stamp.h")
#  include "xrc_build_stamp.h"
#endif
#ifndef XRC_BUILD_STAMP
#  define XRC_BUILD_STAMP "dev"
#endif

// 显示版本（启动日志 / 面板标题统一用它）。
#define XRC_VERSION  @"v10.0"
