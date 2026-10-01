// © 雾月星辰 & MLXC · github@XingChenRS
// XRCSwitchRow.h — 开关行控件（名称 + 状态点）。
// 语义（与 ui-mock/panel_mock.html 对齐）：
//   开=彩色填充+实心点，关=灰底+空心点；长按弹出该项说明（note）。
// 配色由 tone 属性决定（0=默认品红，1=网络青）。
#pragma once

#import <UIKit/UIKit.h>

@interface XRCSwitchRow : UIControl
@property (nonatomic, assign, getter=isOn) BOOL on;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *note;     // 长按弹出的单项说明
@property (nonatomic, assign) NSInteger tone;   // 0=默认（品红） 1=网络（青）
- (instancetype)initWithTitle:(NSString *)title;
@end
