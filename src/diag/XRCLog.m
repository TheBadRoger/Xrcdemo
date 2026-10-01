// © 雾月星辰 & MLXC · github@XingChenRS
// XRCLog.m — 日志实现：级别 × 类别过滤 + 文件落盘（4MB 上限滚动截断）。
#import "XRCLog.h"

#include <stdatomic.h>
#include <string.h>
#include <stdio.h>
#include <dispatch/dispatch.h>

static _Atomic(int)      s_level  = XRCLL_INFO;
static _Atomic(uint32_t) s_cats   = XRCLC_ALL;
static _Atomic(int)      s_preset = 0;          // 0 默认 / 1 verbose / 2 net

#define XRC_LOG_MAX_BYTES  (4u << 20)           // 4MB：超出则截掉前半，保留尾部
#define XRC_LOG_KEEP_BYTES (2u << 20)

// 类别 → 短名（命中多个时取最低位，够用且省事）
static const char *s_cat_name(uint32_t cat) {
    if (cat & XRCLC_BOOT)  return "boot";
    if (cat & XRCLC_BRK)   return "brk";
    if (cat & XRCLC_NET)   return "net";
    if (cat & XRCLC_DL)    return "dl";
    if (cat & XRCLC_JUDGE) return "judge";
    if (cat & XRCLC_AP)    return "ap";
    if (cat & XRCLC_UI)    return "ui";
    if (cat & XRCLC_CB)    return "cb";
    if (cat & XRCLC_OM)    return "om";
    if (cat & XRCLC_PROBE) return "probe";
    return "x";
}

static NSString *s_log_path(void) {
    static NSString *s_path = nil;
    if (!s_path) {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        if (!docs) return nil;
        s_path = [docs stringByAppendingPathComponent:@"xrcdemo.log"];
    }
    return s_path;
}

static void s_append(NSString *out) {
    NSString *path = s_log_path();
    if (!path) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attr = [fm attributesOfItemAtPath:path error:nil];
    if (attr && [attr[NSFileSize] unsignedLongLongValue] > XRC_LOG_MAX_BYTES) {
        // 滚动截断：只保留尾部 KEEP 字节（避免长跑把 Documents 撑爆）
        NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
        if (fh) {
            unsigned long long sz = [attr[NSFileSize] unsignedLongLongValue];
            [fh seekToFileOffset:sz - XRC_LOG_KEEP_BYTES];
            NSData *tail = [fh readDataToEndOfFile];
            [fh closeFile];
            if (tail) [tail writeToFile:path atomically:YES];
        }
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [fh seekToEndOfFile];
    [fh writeData:[out dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

void xrc_logl(uint32_t cat, xrc_log_level_t lvl, NSString *fmt, ...) {
    if (lvl > atomic_load(&s_level)) return;
    uint32_t cats = atomic_load(&s_cats);
    if (cat && !(cat & cats)) return;

    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    if (!msg) return;

    static const char *lname[] = { "err", "warn", "info", "dbg" };
    NSString *tag = [NSString stringWithFormat:@"%s%s", s_cat_name(cat),
                     lvl == XRCLL_INFO ? "" : ([NSString stringWithFormat:@".%s", lname[lvl]].UTF8String)];
    NSString *line = [NSString stringWithFormat:@"[%@] %@", tag, msg];
#if XRC_DEBUG_BUILD
    NSLog(@"[xrcdemo] %@", line);
#endif

    @try {
        static NSDateFormatter *df = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            df = [[NSDateFormatter alloc] init];
            df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        });
        s_append([NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], line]);
    } @catch (NSException *e) { /* 日志自身绝不抛给调用方 */ }
}

void xrc_log(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    if (msg) xrc_logl(XRCLC_MISC, XRCLL_INFO, @"%@", msg);
}

// ---------------- 控制 ----------------
void      xrc_log_set_level(int level) { if (level < 0) level = 0; if (level > 3) level = 3; atomic_store(&s_level, level); }
int       xrc_log_level(void) { return atomic_load(&s_level); }
void      xrc_log_set_cats(uint32_t cats) { atomic_store(&s_cats, cats ? cats : XRCLC_ALL); }
uint32_t  xrc_log_cats(void) { return atomic_load(&s_cats); }

void xrc_log_preset_default(void) { atomic_store(&s_preset, 0); xrc_log_set_level(XRCLL_INFO); xrc_log_set_cats(XRCLC_ALL); }
void xrc_log_preset_verbose(void) { atomic_store(&s_preset, 1); xrc_log_set_level(XRCLL_DEBUG); xrc_log_set_cats(XRCLC_ALL); }
void xrc_log_preset_net(void)     { atomic_store(&s_preset, 2); xrc_log_set_level(XRCLL_DEBUG); xrc_log_set_cats(XRCLC_NET | XRCLC_DL | XRCLC_BOOT | XRCLC_CB); }

const char *xrc_log_preset_name(void) {
    switch (atomic_load(&s_preset)) {
        case 1:  return "verbose";
        case 2:  return "net";
        default: return "default";
    }
}
