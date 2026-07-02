#pragma once

#import <UIKit/UIKit.h>

@class LGSharedBackButtonView;

UIView *LGBackButtonPreferredContainerView(UIView *view);
void LGApplyLowBlurRadiusToView(UIView *view);
void LGApplyLowBlurRadiusToViewWithRadius(UIView *view, CGFloat radius);
UIView *LGMakeLowBlurFallbackView(void);

@interface LGSharedBackButtonView : UIView

- (instancetype)initWithTarget:(id)target action:(SEL)action;
- (instancetype)initWithTarget:(id)target action:(SEL)action symbolName:(NSString *)symbolName;
- (void)setPressed:(BOOL)pressed;
- (void)setGlassEnabled:(BOOL)glassEnabled;
- (void)refreshBackdropAfterScreenUpdates:(BOOL)afterScreenUpdates;
- (void)scheduleBackdropWarmupRefresh;
- (void)cleanupBackdropCapture;

@end
