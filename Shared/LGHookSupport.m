#import "LGHookSupport.h"
#import "LGSharedSupport.h"
#import <objc/runtime.h>

static const NSInteger kLGMaxTraverseDepth = 128;

typedef struct {
    __unsafe_unretained UIView *view;
    NSInteger depth;
} LGViewTraversalEntry;

BOOL LGHasAncestorClass(UIView *view, Class cls) {
    if (!view || !cls) return NO;
    UIView *ancestor = view.superview;
    while (ancestor) {
        if ([ancestor isKindOfClass:cls]) return YES;
        ancestor = ancestor.superview;
    }
    return NO;
}

BOOL LGHasAncestorClassNamed(UIView *view, NSString *className) {
    if (!view || !className.length) return NO;
    UIView *ancestor = view.superview;
    while (ancestor) {
        if ([NSStringFromClass(ancestor.class) isEqualToString:className]) return YES;
        ancestor = ancestor.superview;
    }
    return NO;
}

BOOL LGResponderChainContainsClassNamed(UIResponder *responder, NSString *className) {
    if (!className.length) return NO;
    UIResponder *current = responder;
    while (current) {
        if ([NSStringFromClass(current.class) isEqualToString:className]) return YES;
        current = current.nextResponder;
    }
    return NO;
}

void LGTraverseViews(UIView *root, void (^block)(UIView *view)) {
    if (!root || !block) return;
    NSUInteger capacity = 128;
    NSUInteger count = 1;
    NSMutableData *stackStorage = [NSMutableData dataWithLength:(capacity * sizeof(LGViewTraversalEntry))];
    LGViewTraversalEntry *stack = (LGViewTraversalEntry *)stackStorage.mutableBytes;
    stack[0] = (LGViewTraversalEntry){ .view = root, .depth = 0 };

    while (count > 0) {
        LGViewTraversalEntry entry = stack[--count];
        UIView *view = entry.view;
        NSInteger depth = entry.depth;
        if (!view) continue;
        block(view);
        if (depth >= kLGMaxTraverseDepth) continue;
        NSArray<UIView *> *subviews = view.subviews;
        for (UIView *subview in subviews.reverseObjectEnumerator) {
            if (count >= capacity) {
                capacity *= 2;
                [stackStorage setLength:(capacity * sizeof(LGViewTraversalEntry))];
                stack = (LGViewTraversalEntry *)stackStorage.mutableBytes;
            }
            stack[count++] = (LGViewTraversalEntry){ .view = subview, .depth = depth + 1 };
        }
    }
}

static NSString *LGCustomTintKeyForOverrideKey(NSString *overrideKey) {
    if (!overrideKey.length) return nil;
    NSString *suffix = @".TintOverrideMode";
    if (![overrideKey hasSuffix:suffix]) return nil;
    return [[overrideKey substringToIndex:(overrideKey.length - suffix.length)] stringByAppendingString:@".CustomTintColor"];
}

static UIColor *LGColorFromTintString(NSString *string) {
    NSString *trimmed = [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return nil;
    if ([trimmed hasPrefix:@"#"]) {
        trimmed = [trimmed substringFromIndex:1];
    }
    if ([trimmed hasPrefix:@"0x"] || [trimmed hasPrefix:@"0X"]) {
        trimmed = [trimmed substringFromIndex:2];
    }

    if (trimmed.length == 3 || trimmed.length == 4) {
        NSMutableString *expanded = [NSMutableString stringWithCapacity:(trimmed.length * 2)];
        for (NSUInteger index = 0; index < trimmed.length; index++) {
            unichar character = [trimmed characterAtIndex:index];
            [expanded appendFormat:@"%C%C", character, character];
        }
        trimmed = expanded;
    }

    if (trimmed.length != 6 && trimmed.length != 8) return nil;

    unsigned long long value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    if (![scanner scanHexLongLong:&value] || !scanner.isAtEnd) return nil;

    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 1.0;
    if (trimmed.length == 8) {
        red = (CGFloat)((value >> 24) & 0xFF) / 255.0;
        green = (CGFloat)((value >> 16) & 0xFF) / 255.0;
        blue = (CGFloat)((value >> 8) & 0xFF) / 255.0;
        alpha = (CGFloat)(value & 0xFF) / 255.0;
    } else {
        red = (CGFloat)((value >> 16) & 0xFF) / 255.0;
        green = (CGFloat)((value >> 8) & 0xFF) / 255.0;
        blue = (CGFloat)(value & 0xFF) / 255.0;
    }
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

UIColor *LGCustomTintColorForKey(NSString *key) {
    if (!key.length) return nil;
    return LGColorFromTintString(LG_prefString(key, @""));
}

UIColor *LGDefaultTintColorForViewWithOverrideKey(UIView *view, CGFloat lightAlpha, CGFloat darkAlpha, NSString *overrideKey) {
    UIColor *customTint = LGCustomTintColorForKey(LGCustomTintKeyForOverrideKey(overrideKey));
    if (customTint) return customTint;

    NSString *override = nil;
    if (overrideKey.length) {
        override = LG_prefString(overrideKey, LGTintOverrideSystem);
    }
    if ([override isEqualToString:LGTintOverrideDark]) {
        return [UIColor colorWithWhite:0.0 alpha:darkAlpha];
    }
    if ([override isEqualToString:LGTintOverrideLight]) {
        return [UIColor colorWithWhite:1.0 alpha:lightAlpha];
    }
    if (@available(iOS 12.0, *)) {
        UITraitCollection *traits = view.traitCollection ?: UIScreen.mainScreen.traitCollection;
        if (traits.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:0.0 alpha:darkAlpha];
        }
    }
    return [UIColor colorWithWhite:1.0 alpha:lightAlpha];
}

UIColor *LGDefaultTintColorForView(UIView *view, CGFloat lightAlpha, CGFloat darkAlpha) {
    return LGDefaultTintColorForViewWithOverrideKey(view, lightAlpha, darkAlpha, nil);
}

NSInteger LGPreferredFramesPerSecondForKey(NSString *key, NSInteger minFPS) {
    NSInteger maxFPS = UIScreen.mainScreen.maximumFramesPerSecond > 0
        ? UIScreen.mainScreen.maximumFramesPerSecond
        : 60;
    NSInteger fallback = maxFPS >= 120 ? 120 : 60;
    NSInteger fps = LG_prefInteger(key, fallback);
    if (fps < minFPS) fps = minFPS;
    if (fps > maxFPS) fps = maxFPS;
    return fps;
}

NSInteger LGPreferredLiveCaptureFramesPerSecond(CGFloat framesPerSecond) {
    NSInteger maxFPS = UIScreen.mainScreen.maximumFramesPerSecond > 0
        ? UIScreen.mainScreen.maximumFramesPerSecond
        : 60;
    NSInteger fps = (NSInteger)ceil(MAX(1.0, framesPerSecond));
    return MIN(MAX(fps, 1), maxFPS);
}

UIView *LGEnsureTintOverlayView(UIView *host,
                                const void *associationKey,
                                NSInteger tag,
                                CGRect frame,
                                UIViewAutoresizing autoresizingMask) {
    if (!host || !associationKey) return nil;
    UIView *overlay = objc_getAssociatedObject(host, associationKey);
    if (!overlay) {
        overlay = [[UIView alloc] initWithFrame:frame];
        overlay.userInteractionEnabled = NO;
        overlay.tag = tag;
        overlay.autoresizingMask = autoresizingMask;
        [host addSubview:overlay];
        objc_setAssociatedObject(host, associationKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    overlay.frame = frame;
    return overlay;
}

void LGConfigureTintOverlayView(UIView *overlay,
                                UIColor *backgroundColor,
                                CGFloat cornerRadius,
                                CALayer *referenceLayer,
                                BOOL masksToBounds) {
    if (!overlay) return;
    overlay.backgroundColor = backgroundColor;
    overlay.hidden = (backgroundColor == nil);
    overlay.layer.cornerRadius = cornerRadius;
    overlay.layer.masksToBounds = masksToBounds;
    if (@available(iOS 13.0, *)) {
        if ([referenceLayer respondsToSelector:@selector(cornerCurve)]) {
            overlay.layer.cornerCurve = referenceLayer.cornerCurve;
        }
    }
}

void LGRemoveAssociatedSubview(UIView *host, const void *associationKey) {
    if (!host || !associationKey) return;
    UIView *view = objc_getAssociatedObject(host, associationKey);
    [view removeFromSuperview];
    objc_setAssociatedObject(host, associationKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

@interface LGDisplayLinkDriver : NSObject
@property (nonatomic, copy) dispatch_block_t tickBlock;
- (instancetype)initWithTickBlock:(dispatch_block_t)tickBlock;
- (void)tick:(CADisplayLink *)displayLink;
@end

@implementation LGDisplayLinkDriver

- (instancetype)initWithTickBlock:(dispatch_block_t)tickBlock {
    self = [super init];
    if (!self) return nil;
    _tickBlock = [tickBlock copy];
    return self;
}

- (void)tick:(__unused CADisplayLink *)displayLink {
    if (self.tickBlock) self.tickBlock();
}

@end

@interface LGSharedDisplayLinkHub : NSObject
- (void)tick:(CADisplayLink *)displayLink;
@end

@interface LGDisplayLinkStateBox : NSObject
@property (nonatomic, assign) NSInteger activeCount;
@property (nonatomic, assign) NSInteger preferredFPS;
@property (nonatomic, assign) CFTimeInterval lastTickTimestamp;
@property (nonatomic, assign) NSInteger lastLoggedActiveCount;
@property (nonatomic, assign) BOOL lastLoggedAllowed;
@property (nonatomic, copy) NSString *enabledPreferenceKey;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, strong) id driver;
@end

@implementation LGDisplayLinkStateBox
@end

static CADisplayLink *sSharedDisplayLink = nil;
static LGSharedDisplayLinkHub *sSharedDisplayLinkHub = nil;
static NSMutableArray<LGDisplayLinkStateBox *> *sSharedDisplayLinkStates = nil;
static BOOL sSharedDisplayLinkLastPaused = YES;
static NSInteger sSharedDisplayLinkLastFPS = 0;

static NSString *LGDisplayLinkBoxName(LGDisplayLinkStateBox *box) {
    if (!box) return @"(null)";
    return box.enabledPreferenceKey.length ? box.enabledPreferenceKey : [NSString stringWithFormat:@"%p", box];
}

static NSInteger LGSharedDisplayLinkMaximumFPS(void) {
    NSInteger maxFPS = UIScreen.mainScreen.maximumFramesPerSecond;
    return maxFPS > 0 ? maxFPS : 60;
}

static BOOL LGDisplayLinkBoxPreferenceAllowsUpdates(LGDisplayLinkStateBox *box) {
    if (!box) return NO;
    if (!LG_prefBool(@"DisplayLink.PerSurfaceEnabled", NO)) return YES;
    NSString *key = box.enabledPreferenceKey;
    if (!key.length) return YES;
    return LG_prefBool(key, YES);
}

static BOOL LGDisplayLinkBoxIsActive(LGDisplayLinkStateBox *box) {
    if (!box || box.link != sSharedDisplayLink) return NO;
    if (!LGDisplayLinkBoxPreferenceAllowsUpdates(box)) return NO;
    return box.activeCount > 0;
}

static LGDisplayLinkStateBox *LGDisplayLinkBoxForSourceState(LGDisplayLinkState *state) {
    if (!state) return nil;
    LGDisplayLinkStateBox *box = [state->owner isKindOfClass:LGDisplayLinkStateBox.class] ? state->owner : nil;
    return [sSharedDisplayLinkStates containsObject:box] ? box : nil;
}

static void LGClearDisplayLinkSourceState(LGDisplayLinkState *state) {
    if (!state) return;
    state->link = nil;
    state->driver = nil;
    state->enabledPreferenceKey = nil;
    state->preferredFPS = 0;
    state->lastTickTimestamp = 0.0;
    state->lastLoggedActiveCount = 0;
    state->lastLoggedAllowed = NO;
    state->owner = nil;
}

static void LGStopSharedDisplayLinkIfIdle(void) {
    if (sSharedDisplayLinkStates.count > 0) return;
    [sSharedDisplayLink invalidate];
    sSharedDisplayLink = nil;
    sSharedDisplayLinkHub = nil;
}

static void LGReconfigureSharedDisplayLinkFPS(void) {
    if (!sSharedDisplayLink) return;
    NSInteger highestFPS = 0;
    BOOL hasActiveStates = NO;
    for (LGDisplayLinkStateBox *box in sSharedDisplayLinkStates) {
        if (!LGDisplayLinkBoxIsActive(box)) continue;
        hasActiveStates = YES;
        highestFPS = MAX(highestFPS, box.preferredFPS);
    }
    if (!hasActiveStates || highestFPS <= 0) {
        sSharedDisplayLink.paused = YES;
        if (!sSharedDisplayLinkLastPaused) {
            LGDebugLog(@"displaylink shared paused states=%lu", (unsigned long)sSharedDisplayLinkStates.count);
        }
        sSharedDisplayLinkLastPaused = YES;
        sSharedDisplayLinkLastFPS = 0;
        return;
    }
    sSharedDisplayLink.paused = NO;
    NSInteger cappedFPS = MIN(MAX(highestFPS, 1), LGSharedDisplayLinkMaximumFPS());
    if ([sSharedDisplayLink respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
        sSharedDisplayLink.preferredFramesPerSecond = cappedFPS;
    }
    if (sSharedDisplayLinkLastPaused || sSharedDisplayLinkLastFPS != cappedFPS) {
        LGDebugLog(@"displaylink shared active fps=%ld states=%lu",
                   (long)cappedFPS,
                   (unsigned long)sSharedDisplayLinkStates.count);
    }
    sSharedDisplayLinkLastPaused = NO;
    sSharedDisplayLinkLastFPS = cappedFPS;
}

@implementation LGSharedDisplayLinkHub

- (void)tick:(CADisplayLink *)displayLink {
    NSArray<LGDisplayLinkStateBox *> *states = [sSharedDisplayLinkStates copy];
    for (LGDisplayLinkStateBox *box in states) {
        if (!LGDisplayLinkBoxIsActive(box)) continue;

        NSInteger preferredFPS = MAX(box.preferredFPS, 1);
        CFTimeInterval minimumInterval = 1.0 / (CFTimeInterval)preferredFPS;
        if (box.lastTickTimestamp > 0.0) {
            CFTimeInterval delta = displayLink.timestamp - box.lastTickTimestamp;
            if (delta + 0.0005 < minimumInterval) continue;
        }
        box.lastTickTimestamp = displayLink.timestamp;

        LGDisplayLinkDriver *driver = box.driver;
        if (driver) [driver tick:displayLink];
    }
}

@end

static void LGEnsureSharedDisplayLink(void) {
    static dispatch_once_t prefsOnceToken;
    dispatch_once(&prefsOnceToken, ^{
        LGObservePreferenceChanges(^{
            LGReconfigureSharedDisplayLinkFPS();
        });
    });
    if (!sSharedDisplayLinkStates) {
        sSharedDisplayLinkStates = [NSMutableArray array];
    }
    if (sSharedDisplayLink) return;
    sSharedDisplayLinkHub = [LGSharedDisplayLinkHub new];
    sSharedDisplayLink = [CADisplayLink displayLinkWithTarget:sSharedDisplayLinkHub selector:@selector(tick:)];
    sSharedDisplayLink.paused = YES;
    [sSharedDisplayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

void LGStartDisplayLink(CADisplayLink *__strong *linkStorage,
                        id __strong *driverStorage,
                        NSInteger preferredFPS,
                        dispatch_block_t tickBlock) {
    LGAssertMainThread();
    if (!linkStorage || !driverStorage || *linkStorage) return;
    LGDisplayLinkDriver *driver = [[LGDisplayLinkDriver alloc] initWithTickBlock:tickBlock];
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:driver selector:@selector(tick:)];
    if ([link respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
        link.preferredFramesPerSecond = preferredFPS;
    }
    [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    *driverStorage = driver;
    *linkStorage = link;
    LGDebugLog(@"displaylink direct start link=%p fps=%ld", link, (long)preferredFPS);
}

void LGStopDisplayLink(CADisplayLink *__strong *linkStorage,
                       id __strong *driverStorage) {
    LGAssertMainThread();
    if (!linkStorage || !*linkStorage) return;
    LGDebugLog(@"displaylink direct stop link=%p", *linkStorage);
    [*linkStorage invalidate];
    *linkStorage = nil;
    if (driverStorage) *driverStorage = nil;
}

void LGStartDisplayLinkState(LGDisplayLinkState *state,
                             NSInteger preferredFPS,
                             dispatch_block_t tickBlock) {
    LGStartDisplayLinkStateWithPreferenceKey(state, preferredFPS, nil, tickBlock);
}

void LGStartDisplayLinkStateWithPreferenceKey(LGDisplayLinkState *state,
                                              NSInteger preferredFPS,
                                              NSString *enabledPreferenceKey,
                                              dispatch_block_t tickBlock) {
    LGAssertMainThread();
    if (!state) return;
    if (state->link) return;
    LGEnsureSharedDisplayLink();
    LGDisplayLinkDriver *driver = [[LGDisplayLinkDriver alloc] initWithTickBlock:tickBlock];
    LGDisplayLinkStateBox *box = [LGDisplayLinkStateBox new];
    box.activeCount = state->activeCount;
    box.driver = driver;
    box.enabledPreferenceKey = [enabledPreferenceKey copy];
    box.preferredFPS = MIN(MAX(preferredFPS, 1), LGSharedDisplayLinkMaximumFPS());
    box.lastTickTimestamp = 0.0;
    box.lastLoggedActiveCount = NSIntegerMin;
    box.lastLoggedAllowed = NO;
    box.link = sSharedDisplayLink;
    [sSharedDisplayLinkStates addObject:box];
    state->driver = box.driver;
    state->enabledPreferenceKey = box.enabledPreferenceKey;
    state->preferredFPS = box.preferredFPS;
    state->lastTickTimestamp = box.lastTickTimestamp;
    state->lastLoggedActiveCount = box.lastLoggedActiveCount;
    state->lastLoggedAllowed = box.lastLoggedAllowed;
    state->link = box.link;
    state->owner = box;
    LGDebugLog(@"displaylink state start name=%@ fps=%ld active=%ld allowed=%d",
               LGDisplayLinkBoxName(box),
               (long)box.preferredFPS,
               (long)box.activeCount,
               LGDisplayLinkBoxPreferenceAllowsUpdates(box));
    LGReconfigureSharedDisplayLinkFPS();
}

void LGStopDisplayLinkState(LGDisplayLinkState *state) {
    LGAssertMainThread();
    if (!state) return;
    if (!state->link) return;
    LGDisplayLinkStateBox *box = LGDisplayLinkBoxForSourceState(state);
    LGDebugLog(@"displaylink state stop name=%@ active=%ld fps=%ld",
               box ? LGDisplayLinkBoxName(box) : [NSString stringWithFormat:@"%p", state],
               (long)(box ? box.activeCount : state->activeCount),
               (long)(box ? box.preferredFPS : state->preferredFPS));
    for (NSInteger index = sSharedDisplayLinkStates.count - 1; index >= 0; index--) {
        LGDisplayLinkStateBox *candidate = sSharedDisplayLinkStates[index];
        if (candidate == box) {
            [sSharedDisplayLinkStates removeObjectAtIndex:index];
        }
    }
    LGClearDisplayLinkSourceState(state);
    LGReconfigureSharedDisplayLinkFPS();
    LGStopSharedDisplayLinkIfIdle();
}

void LGDisplayLinkStateDidChangeActivity(LGDisplayLinkState *state) {
    LGAssertMainThread();
    if (!state || state->link != sSharedDisplayLink) return;
    if (!sSharedDisplayLink) return;
    LGDisplayLinkStateBox *box = LGDisplayLinkBoxForSourceState(state);
    if (!box) return;
    box.activeCount = state->activeCount;
    if (box.activeCount <= 0) {
        box.lastTickTimestamp = 0.0;
    }
    state->lastTickTimestamp = box.lastTickTimestamp;
    BOOL allowed = LGDisplayLinkBoxPreferenceAllowsUpdates(box);
    if (box.lastLoggedActiveCount != box.activeCount || box.lastLoggedAllowed != allowed) {
        LGDebugLog(@"displaylink state activity name=%@ active=%ld fps=%ld allowed=%d",
                   LGDisplayLinkBoxName(box),
                   (long)box.activeCount,
                   (long)box.preferredFPS,
                   allowed);
        box.lastLoggedActiveCount = box.activeCount;
        box.lastLoggedAllowed = allowed;
        state->lastLoggedActiveCount = box.lastLoggedActiveCount;
        state->lastLoggedAllowed = box.lastLoggedAllowed;
    }
    LGReconfigureSharedDisplayLinkFPS();
}

void LGSetDisplayLinkStatePreferredFPS(LGDisplayLinkState *state, NSInteger preferredFPS) {
    LGAssertMainThread();
    if (!state) return;
    LGDisplayLinkStateBox *box = LGDisplayLinkBoxForSourceState(state);
    NSInteger cappedFPS = MIN(MAX(preferredFPS, 1), LGSharedDisplayLinkMaximumFPS());
    if (box) {
        if (box.preferredFPS == cappedFPS) return;
        box.preferredFPS = cappedFPS;
        box.lastTickTimestamp = 0.0;
        state->preferredFPS = box.preferredFPS;
        state->lastTickTimestamp = box.lastTickTimestamp;
    } else {
        if (state->preferredFPS == cappedFPS) return;
        state->preferredFPS = cappedFPS;
        state->lastTickTimestamp = 0.0;
    }
    LGDebugLog(@"displaylink state fps name=%@ fps=%ld active=%ld allowed=%d",
               box ? LGDisplayLinkBoxName(box) : [NSString stringWithFormat:@"%p", state],
               (long)cappedFPS,
               (long)(box ? box.activeCount : state->activeCount),
               box ? LGDisplayLinkBoxPreferenceAllowsUpdates(box) : YES);
    LGReconfigureSharedDisplayLinkFPS();
}
