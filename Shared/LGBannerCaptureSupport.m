#import "LGBannerCaptureSupport.h"
#import "../LiquidGlass.h"
#import "../Runtime/LGSnapshotCaptureSupport.h"
#import "LGSharedSupport.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface LGLiveBackdropCaptureView : UIView
@end

@implementation LGLiveBackdropCaptureView

+ (Class)layerClass {
    return NSClassFromString(@"CABackdropLayer") ?: [CALayer class];
}

- (void)lg_configureBackdropLayerIfNeeded {
    Class backdropCls = NSClassFromString(@"CABackdropLayer");
    CALayer *layer = self.layer;
    if (!backdropCls || ![layer isKindOfClass:backdropCls]) return;
    @try {
        [layer setValue:@NO forKey:@"layerUsesCoreImageFilters"];
        [layer setValue:@YES forKey:@"windowServerAware"];
        [layer setValue:NSUUID.UUID.UUIDString forKey:@"groupName"];
    } @catch (NSException *exception) {
        LGDebugLog(@"banner backdrop layer configuration failed %@ %@", exception.name, exception.reason);
    }
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    [self lg_configureBackdropLayerIfNeeded];
    return self;
}

@end

static void *kLGLiveCaptureUsesModelGeometryKey = &kLGLiveCaptureUsesModelGeometryKey;

void LGSetLiveBackdropCaptureUsesModelGeometry(UIView *host, BOOL usesModelGeometry) {
    if (!host) return;
    objc_setAssociatedObject(host,
                             kLGLiveCaptureUsesModelGeometryKey,
                             usesModelGeometry ? @YES : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static CGFloat LGLiveCaptureScaleForRect(CGRect captureRect, CGFloat screenScale) {
    CGFloat configuredScale = LG_prefFloat(@"LiveCapture.ScaleFactor", 0.35);
    CGFloat minimumScale = LG_prefFloat(@"LiveCapture.MinimumScale", 0.55);
    CGFloat maximumScale = LG_prefFloat(@"LiveCapture.MaximumScale", 1.0);
    CGFloat maximumPixels = LG_prefFloat(@"LiveCapture.MaximumPixels", 180000.0);

    CGFloat captureScale = screenScale * MAX(0.1, configuredScale);
    captureScale = MIN(MAX(captureScale, MAX(0.1, minimumScale)), MAX(0.1, maximumScale));

    CGFloat width = CGRectGetWidth(captureRect);
    CGFloat height = CGRectGetHeight(captureRect);
    CGFloat estimatedPixels = width * height * captureScale * captureScale;
    if (maximumPixels > 1000.0 && estimatedPixels > maximumPixels) {
        captureScale *= sqrt(maximumPixels / estimatedPixels);
        captureScale = MAX(0.1, captureScale);
    }
    return captureScale;
}

void LGRemoveLiveBackdropCaptureView(UIView *host, const void *associationKey) {
    LGAssertMainThread();
    if (!host || !associationKey) return;
    UIView *backdropView = objc_getAssociatedObject(host, associationKey);
    [backdropView removeFromSuperview];
    objc_setAssociatedObject(host, associationKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

BOOL LGCaptureLiveBackdropTextureForHost(UIView *host,
                                         LiquidGlassView *glass,
                                         const void *associationKey,
                                         CGPoint *outOrigin,
                                         CGSize *outSamplingResolution) {
    LGAssertMainThread();
    UIView *superview = host.superview;
    if (!host || !glass || !associationKey) {
        LGDebugLog(@"live capture bail reason=invalid-args host=%@", host ? NSStringFromClass(host.class) : @"(null)");
        return NO;
    }
    if (!superview || !host.window) {
        LGDebugLog(@"live capture bail reason=no-window-or-superview host=%@ window=%d superview=%d",
                   NSStringFromClass(host.class),
                   host.window ? 1 : 0,
                   superview ? 1 : 0);
        return NO;
    }

    BOOL usesModelGeometry = [objc_getAssociatedObject(host, kLGLiveCaptureUsesModelGeometryKey) boolValue];
    CGRect hostFrame = CGRectZero;
    if (usesModelGeometry) {
        CALayer *hostLayer = host.layer;
        CGSize size = hostLayer.bounds.size;
        CGPoint anchor = hostLayer.anchorPoint;
        CGPoint position = hostLayer.position;
        hostFrame = CGRectMake(position.x - size.width * anchor.x,
                               position.y - size.height * anchor.y,
                               size.width,
                               size.height);
    } else {
        CALayer *hostLayer = host.layer.presentationLayer ?: host.layer;
        hostFrame = [hostLayer convertRect:hostLayer.bounds toLayer:superview.layer];
    }
    CGSize captureSize = hostFrame.size;
    CGPoint captureOrigin = hostFrame.origin;
    if (!isfinite(captureSize.width) || !isfinite(captureSize.height) ||
        !isfinite(captureOrigin.x) || !isfinite(captureOrigin.y) ||
        captureSize.width <= 1.0f || captureSize.height <= 1.0f) {
        LGDebugLog(@"live capture bail reason=invalid-host-frame host=%@ frame=%@",
                   NSStringFromClass(host.class),
                   NSStringFromCGRect(hostFrame));
        return NO;
    }

    CGRect captureRect = (CGRect){ captureOrigin, captureSize };
    CGRect captureRectInScreen = CGRectZero;
    if (@available(iOS 13.0, *)) {
        captureRectInScreen = [superview convertRect:captureRect toCoordinateSpace:UIScreen.mainScreen.coordinateSpace];
    } else {
        captureRectInScreen = [superview convertRect:captureRect toView:nil];
    }
    if (!isfinite(CGRectGetMinX(captureRectInScreen)) ||
        !isfinite(CGRectGetMinY(captureRectInScreen)) ||
        !isfinite(CGRectGetWidth(captureRectInScreen)) ||
        !isfinite(CGRectGetHeight(captureRectInScreen)) ||
        CGRectGetWidth(captureRectInScreen) <= 1.0f ||
        CGRectGetHeight(captureRectInScreen) <= 1.0f) {
        LGDebugLog(@"live capture bail reason=invalid-screen-rect host=%@ rect=%@",
                   NSStringFromClass(host.class),
                   NSStringFromCGRect(captureRectInScreen));
        return NO;
    }
    LGLiveBackdropCaptureView *backdropView = objc_getAssociatedObject(host, associationKey);
    if (!backdropView) {
        backdropView = [[LGLiveBackdropCaptureView alloc] initWithFrame:captureRect];
        objc_setAssociatedObject(host, associationKey, backdropView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    backdropView.frame = captureRect;
    @try {
        if (backdropView.superview != superview) {
            [superview insertSubview:backdropView belowSubview:host];
        } else {
            NSInteger hostIndex = [superview.subviews indexOfObjectIdenticalTo:host];
            NSInteger backdropIndex = [superview.subviews indexOfObjectIdenticalTo:backdropView];
            if (hostIndex != NSNotFound && backdropIndex != NSNotFound && backdropIndex >= hostIndex) {
                [superview insertSubview:backdropView belowSubview:host];
            }
        }
    } @catch (NSException *exception) {
        LGDebugLog(@"live capture bail reason=insert-exception host=%@ superview=%@ exception=%@",
                   NSStringFromClass(host.class),
                   NSStringFromClass(superview.class),
                   exception.reason ?: exception.name);
        [backdropView removeFromSuperview];
        return NO;
    }

    CGFloat screenScale = host.window.screen.scale ?: UIScreen.mainScreen.scale ?: 2.0f;
    CGFloat captureScale = LGLiveCaptureScaleForRect(captureRect, screenScale);
    size_t pixelWidth = MAX((size_t)1, (size_t)lrint(CGRectGetWidth(captureRect) * captureScale));
    size_t pixelHeight = MAX((size_t)1, (size_t)lrint(CGRectGetHeight(captureRect) * captureScale));

    __block BOOL ok = NO;
    [glass updateWallpaperTextureWithPixelWidth:pixelWidth
                                         height:pixelHeight
                                 sourcePixelSize:CGSizeMake((CGFloat)pixelWidth, (CGFloat)pixelHeight)
                                        actions:^(CGContextRef ctx) {
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, 0.0f, (CGFloat)pixelHeight);
        CGContextScaleCTM(ctx, captureScale, -captureScale);
        UIGraphicsPushContext(ctx);
        ok = LGDrawViewHierarchyIntoCurrentContext(backdropView, backdropView.bounds, NO);
        UIGraphicsPopContext();
        CGContextRestoreGState(ctx);
    }];
    if (!ok) {
        LGDebugLog(@"live capture bail reason=draw-failed host=%@ rect=%@ px=%zux%zu",
                   NSStringFromClass(host.class),
                   NSStringFromCGRect(captureRectInScreen),
                   pixelWidth,
                   pixelHeight);
        return NO;
    }

    if (outOrigin) *outOrigin = captureRectInScreen.origin;
    if (outSamplingResolution) {
        *outSamplingResolution = CGSizeMake(CGRectGetWidth(captureRectInScreen) * screenScale,
                                            CGRectGetHeight(captureRectInScreen) * screenScale);
    }
    return YES;
}

BOOL LGApplyRenderingModeToGlassHost(UIView *host,
                                     LiquidGlassView *glass,
                                     NSString *renderingModeKey,
                                     const void *associationKey,
                                     UIImage *snapshot,
                                     CGPoint snapshotOrigin) {
    LGAssertMainThread();
    if (!host || !glass || !renderingModeKey.length || !associationKey) {
        LGDebugLog(@"rendering mode bail reason=invalid-args key=%@ host=%@",
                   renderingModeKey ?: @"(null)",
                   host ? NSStringFromClass(host.class) : @"(null)");
        return NO;
    }

    NSString *resolvedMode = LG_prefString(renderingModeKey, LGDefaultRenderingModeForKey(renderingModeKey));
    BOOL prefersLiveCapture = [resolvedMode isEqualToString:LGRenderingModeLiveCapture];
    LGDebugLog(@"rendering mode resolve key=%@ mode=%@ host=%@ snapshot=%d",
               renderingModeKey,
               resolvedMode,
               NSStringFromClass(host.class),
               snapshot ? 1 : 0);

    if (prefersLiveCapture) {
        CGPoint captureOrigin = CGPointZero;
        CGSize samplingResolution = CGSizeZero;
        if (LGCaptureLiveBackdropTextureForHost(host,
                                                glass,
                                                associationKey,
                                                &captureOrigin,
                                                &samplingResolution)) {
            LGDebugLog(@"rendering mode live ok key=%@ host=%@ origin=%@ sampling=%@",
                       renderingModeKey,
                       NSStringFromClass(host.class),
                       NSStringFromCGPoint(captureOrigin),
                       NSStringFromCGSize(samplingResolution));
            glass.wallpaperOrigin = captureOrigin;
            glass.wallpaperSamplingResolution = samplingResolution;
            [glass updateOrigin];
            return YES;
        }
        LGRemoveLiveBackdropCaptureView(host, associationKey);
        if (!snapshot) {
            LGDebugLog(@"rendering mode live bail reason=no-fallback-snapshot key=%@ host=%@",
                       renderingModeKey,
                       NSStringFromClass(host.class));
            return NO;
        }
        LGDebugLog(@"rendering mode live fallback key=%@ host=%@ fallback=snapshot",
                   renderingModeKey,
                   NSStringFromClass(host.class));
    } else {
        LGRemoveLiveBackdropCaptureView(host, associationKey);
    }

    if (!snapshot) {
        LGDebugLog(@"rendering mode snapshot bail reason=no-snapshot key=%@ host=%@",
                   renderingModeKey,
                   NSStringFromClass(host.class));
        return NO;
    }
    glass.wallpaperImage = snapshot;
    glass.wallpaperOrigin = snapshotOrigin;
    glass.wallpaperSamplingResolution = CGSizeZero;
    [glass updateOrigin];
    LGDebugLog(@"rendering mode snapshot ok key=%@ host=%@ origin=%@ size=%@",
               renderingModeKey,
               NSStringFromClass(host.class),
               NSStringFromCGPoint(snapshotOrigin),
               NSStringFromCGSize(snapshot.size));
    return YES;
}

BOOL LGShouldRefreshLiveCaptureForHost(UIView *host,
                                       NSString *renderingModeKey,
                                       const void *lastCaptureTimeKey,
                                       CGFloat framesPerSecond,
                                       BOOL hadGlass) {
    if (!host || !renderingModeKey.length || !lastCaptureTimeKey) return YES;
    if (!LG_prefersLiveCapture(renderingModeKey)) return YES;
    if (!hadGlass) return YES;

    CGFloat fps = MAX(1.0, framesPerSecond);
    NSNumber *lastCaptureNumber = objc_getAssociatedObject(host, lastCaptureTimeKey);
    if (!lastCaptureNumber) return YES;

    CFTimeInterval now = CACurrentMediaTime();
    return (now - lastCaptureNumber.doubleValue) >= (1.0 / fps);
}

void LGMarkLiveCaptureRefreshedForHost(UIView *host, const void *lastCaptureTimeKey) {
    if (!host || !lastCaptureTimeKey) return;
    objc_setAssociatedObject(host,
                             lastCaptureTimeKey,
                             @(CACurrentMediaTime()),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
