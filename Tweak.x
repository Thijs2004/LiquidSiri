#import <UIKit/UIKit.h>
#import "LiquidGlass.h"
#import "LiquidSiri-Swift.h"

#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>

@interface LGAudioAnalyzer : NSObject
+ (instancetype)sharedInstance;
- (void)startAnalyzing;
- (void)stopAnalyzing;
@end

@interface SiriBackdropCaptureView : UIView
@end

@interface MTMaterialView : UIView
@end

static void sendPowerToSpringBoard(float level);
static NSInteger globalSiriState = 1;

@implementation SiriBackdropCaptureView
+ (Class)layerClass { return NSClassFromString(@"CABackdropLayer") ?: [CALayer class]; }
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        CALayer *layer = self.layer;
        Class backdropCls = NSClassFromString(@"CABackdropLayer");
        if (backdropCls && [layer isKindOfClass:backdropCls]) {
            [layer setValue:@NO forKey:@"layerUsesCoreImageFilters"];
            [layer setValue:@YES forKey:@"windowServerAware"];
            [layer setValue:NSUUID.UUID.UUIDString forKey:@"groupName"];
            // Critical: Remove the default blur filters so it captures the raw screen!
            layer.filters = nil;
        }
    }
    return self;
}
@end

@interface SiriUIBackgroundBlurViewController : UIViewController
@property (nonatomic, strong) LiquidGlassView *glassOrbView;
@property (nonatomic, strong) SiriBackdropCaptureView *backdropView;
@property (nonatomic, strong) UIView *glowLineView;
@property (nonatomic, strong) UIView *externalWhiteGlowView;
@property (nonatomic, strong) UIImage *capturedWallpaper;
@property (nonatomic, assign) BOOL hasCapturedBackdrop;
@property (nonatomic, strong) UIView *lgEditorPanel;
@property (nonatomic, strong) UISlider *sliderWidth;
@property (nonatomic, strong) UISlider *sliderHeight;
@property (nonatomic, strong) UISlider *sliderScale;
@property (nonatomic, strong) UISlider *sliderY;
@property (nonatomic, strong) UISlider *sliderCorner;
@property (nonatomic, strong) UISlider *sliderRefraction;
- (void)liquidSiriToggleEditor:(UILongPressGestureRecognizer *)gesture;
- (UISlider *)createSliderWithTitle:(NSString *)title min:(float)min max:(float)max val:(float)val y:(CGFloat)y inPanel:(UIView *)panel;
- (void)liquidSiriSetupEditor;
- (void)liquidSiriSaveSettings:(UIButton *)btn;
- (void)liquidSiriSliderChanged:(UISlider *)slider;
@end

void LG_registerGlassView(UIView *view, LGUpdateGroup group) {}
void LG_unregisterGlassView(UIView *view, LGUpdateGroup group) {}
void LG_updateRegisteredGlassViews(LGUpdateGroup group) {}
void LG_redrawRegisteredGlassViews(LGUpdateGroup group) {}

%hook SUICOrbView

- (id)initWithFrame:(CGRect)arg1 {
    id view = %orig(arg1);
    if ([view isKindOfClass:[UIView class]]) {
        [(UIView *)view setAlpha:0.0];
    }
    return view;
}

- (void)setMode:(NSInteger)mode {
    %orig;
    globalSiriState = mode;
}

- (void)setPowerLevel:(float)arg1 {
    %orig;
    float level = arg1;
    
    BOOL speaking = NO;
    if (globalSiriState == 3) {
        speaking = YES;
    }
    
    @try {
        id audioSession = [NSClassFromString(@"AVAudioSession") sharedInstance];
        if (audioSession) {
            NSString *audioMode = [audioSession valueForKey:@"mode"];
            if ([audioMode isEqualToString:@"VoicePrompt"]) {
                speaking = YES;
            }
        }
    } @catch (NSException *e) {}
    
    if (speaking) {
        level = 0.0;
    }
    
    sendPowerToSpringBoard(level);
}

%end

static NSArray *generateWavePaths(CGRect bounds, CGFloat amplitude, CGFloat frequency, NSInteger steps) {
    NSMutableArray *paths = [NSMutableArray array];
    NSInteger segments = 40; 
    CGFloat stepX = bounds.size.width / (CGFloat)segments;
    
    for (NSInteger step = 0; step < steps; step++) {
        CGFloat phase = (CGFloat)step / (CGFloat)steps * 2.0 * M_PI;
        
        UIBezierPath *path = [UIBezierPath bezierPath];
        for (NSInteger i = 0; i <= segments; i++) {
            CGFloat x = i * stepX;
            CGFloat normalizedX = x / bounds.size.width;
            
            // Gentler taper envelope so they don't pinch completely to zero too fast
            CGFloat envelope = sin(normalizedX * M_PI);
            envelope = pow(envelope, 0.7); // Makes the center wider
            
            CGFloat y = bounds.size.height/2.0 + (amplitude * envelope) * sin(normalizedX * frequency * 2.0 * M_PI + phase);
            
            if (i == 0) {
                [path moveToPoint:CGPointMake(x, y)];
            } else {
                [path addLineToPoint:CGPointMake(x, y)];
            }
        }
        [paths addObject:(id)path.CGPath];
    }
    return paths;
}

OBJC_EXTERN UIImage *_UICreateScreenUIImage(void);

%hook SiriUIBackgroundBlurViewController

%property (nonatomic, strong) LiquidGlassView *glassOrbView;
%property (nonatomic, strong) SiriBackdropCaptureView *backdropView;
%property (nonatomic, strong) UIView *glowLineView;
%property (nonatomic, strong) UIView *externalWhiteGlowView;
%property (nonatomic, strong) UIImage *capturedWallpaper;
%property (nonatomic, assign) BOOL hasCapturedBackdrop;
%property (nonatomic, strong) UIView *lgEditorPanel;
%property (nonatomic, strong) UISlider *sliderWidth;
%property (nonatomic, strong) UISlider *sliderHeight;
%property (nonatomic, strong) UISlider *sliderScale;
%property (nonatomic, strong) UISlider *sliderY;
%property (nonatomic, strong) UISlider *sliderCorner;
%property (nonatomic, strong) UISlider *sliderRefraction;

- (void)viewDidLoad {
    %orig;
    
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(liquidSiriToggleEditor:)];
    longPress.minimumPressDuration = 0.5;
    [self.view addGestureRecognizer:longPress];
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat width = 154.0;
    CGFloat height = 105.0;
    CGRect orbFrame = CGRectMake((screenBounds.size.width - width)/2.0, 35, width, height);
    
    UIGraphicsBeginImageContextWithOptions(screenBounds.size, NO, 0.0);
    UIImage *tempBg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    self.glassOrbView = [[LiquidGlassView alloc] initWithFrame:orbFrame wallpaper:tempBg wallpaperOrigin:CGPointZero];
    self.glassOrbView.updateGroup = 255; // Unregistered group so liquidass preferences don't overwrite our glass thickness
    
    // Physical glass parameters: 
    // Restored refraction now that the rogue view transform is removed.
    // Significantly increased bezelWidth to give the glass thick, heavy edges.
    self.glassOrbView.refractionScale = 1.4; // More bending
    self.glassOrbView.refractiveIndex = 1.15;
    self.glassOrbView.specularOpacity = 1.0; // Max presence
    self.glassOrbView.blur = 0.0; // User requested to completely remove the blur
    self.glassOrbView.bezelWidth = 24.0; // Extremely thick heavy edges
    self.glassOrbView.glassThickness = 120.0;
    
    // Add physical depth
    self.glassOrbView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.glassOrbView.layer.shadowOffset = CGSizeMake(0, 6);
    self.glassOrbView.layer.shadowOpacity = 0.4;
    self.glassOrbView.layer.shadowRadius = 12;
    [self.view addSubview:self.glassOrbView];
    
    // Add external white glow behind the bottom of the glass
    self.externalWhiteGlowView = [[UIView alloc] initWithFrame:CGRectMake(orbFrame.origin.x + width * 0.15, orbFrame.origin.y + height - 35.0, width * 0.7, 30.0)];
    self.externalWhiteGlowView.backgroundColor = [UIColor clearColor]; // Clear background to hide the solid shape
    UIBezierPath *shadowPath = [UIBezierPath bezierPathWithOvalInRect:self.externalWhiteGlowView.bounds];
    self.externalWhiteGlowView.layer.shadowPath = shadowPath.CGPath;
    self.externalWhiteGlowView.layer.shadowColor = [UIColor whiteColor].CGColor;
    self.externalWhiteGlowView.layer.shadowOffset = CGSizeZero;
    self.externalWhiteGlowView.layer.shadowOpacity = 0.65; // Slightly dialed back opacity
    self.externalWhiteGlowView.layer.shadowRadius = 12.0; // Tighter glow radius
    self.externalWhiteGlowView.alpha = 0.0;
    [self.view insertSubview:self.externalWhiteGlowView belowSubview:self.glassOrbView];
    
    // Siri wave container (expanded to the full orb size to prevent clipping the underglow)
    self.glowLineView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    self.glowLineView.backgroundColor = [UIColor clearColor];
    self.glowLineView.clipsToBounds = NO;
    [self.glassOrbView addSubview:self.glowLineView];
    
    self.glassOrbView.alpha = 0.0;
}

%new
- (void)liquidSiriToggleEditor:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (!self.lgEditorPanel) {
            [self liquidSiriSetupEditor];
        }
        
        BOOL isHidden = self.lgEditorPanel.alpha < 0.5;
        [UIView animateWithDuration:0.3 animations:^{
            self.lgEditorPanel.alpha = isHidden ? 1.0 : 0.0;
        }];
    }
}

%new
- (UISlider *)createSliderWithTitle:(NSString *)title min:(float)min max:(float)max val:(float)val y:(CGFloat)y inPanel:(UIView *)panel {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(15, y, panel.bounds.size.width - 30, 20)];
    lbl.text = title;
    lbl.font = [UIFont systemFontOfSize:14];
    [panel addSubview:lbl];
    
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(15, y + 25, panel.bounds.size.width - 30, 30)];
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = val;
    [slider addTarget:self action:@selector(liquidSiriSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:slider];
    return slider;
}

%new
- (void)liquidSiriSetupEditor {
    CGFloat panelW = 240;
    CGFloat panelH = 460;
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - panelW - 10, 80, panelW, panelH)];
    panel.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.95];
    panel.layer.cornerRadius = 20;
    panel.layer.shadowColor = [UIColor blackColor].CGColor;
    panel.layer.shadowOpacity = 0.3;
    panel.layer.shadowRadius = 10;
    panel.alpha = 0.0;
    [self.view addSubview:panel];
    self.lgEditorPanel = panel;
    
    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, panelW, 30)];
    header.text = @"Liquid Glass Live Editor";
    header.textAlignment = NSTextAlignmentCenter;
    header.font = [UIFont boldSystemFontOfSize:18];
    [panel addSubview:header];
    
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.yourcompany.liquidsiri.prefs.plist"];
    if (!prefs) prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.yourcompany.liquidsiri.prefs.plist"];
    
    CGFloat curScale = prefs[@"orbScale"] ? [prefs[@"orbScale"] floatValue] : 1.0;
    CGFloat curY = prefs[@"yOffset"] ? [prefs[@"yOffset"] floatValue] : 0.0;
    CGFloat curW = prefs[@"customWidth"] ? [prefs[@"customWidth"] floatValue] : 1.0;
    CGFloat curH = prefs[@"customHeight"] ? [prefs[@"customHeight"] floatValue] : 1.0;
    CGFloat curCorner = prefs[@"customCorner"] ? [prefs[@"customCorner"] floatValue] : 1.0;
    CGFloat curRefrac = prefs[@"customRefraction"] ? [prefs[@"customRefraction"] floatValue] : 1.4;

    CGFloat y = 50;
    self.sliderScale = [self createSliderWithTitle:@"整体 Scale" min:0.5 max:2.5 val:curScale y:y inPanel:panel]; y += 55;
    self.sliderY = [self createSliderWithTitle:@"整体 Y 位置" min:-200 max:200 val:curY y:y inPanel:panel]; y += 55;
    self.sliderWidth = [self createSliderWithTitle:@"宽 Width" min:0.5 max:2.5 val:curW y:y inPanel:panel]; y += 55;
    self.sliderHeight = [self createSliderWithTitle:@"高 Height" min:0.5 max:2.5 val:curH y:y inPanel:panel]; y += 55;
    self.sliderCorner = [self createSliderWithTitle:@"圆角 Corner Radius" min:0.0 max:2.0 val:curCorner y:y inPanel:panel]; y += 55;
    self.sliderRefraction = [self createSliderWithTitle:@"强度 Refraction" min:0.0 max:5.0 val:curRefrac y:y inPanel:panel]; y += 65;

    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(15, y, panelW/2 - 20, 40);
    saveBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1.0];
    [saveBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [saveBtn setTitle:@"Save" forState:UIControlStateNormal];
    saveBtn.layer.cornerRadius = 10;
    [saveBtn addTarget:self action:@selector(liquidSiriSaveSettings:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:saveBtn];
    
    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    resetBtn.frame = CGRectMake(panelW/2 + 5, y, panelW/2 - 20, 40);
    resetBtn.backgroundColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];
    [resetBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [resetBtn setTitle:@"Reset All" forState:UIControlStateNormal];
    resetBtn.layer.cornerRadius = 10;
    [resetBtn addTarget:self action:@selector(liquidSiriResetSettings:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:resetBtn];
}

%new
- (void)liquidSiriResetSettings:(UIButton *)btn {
    self.sliderScale.value = 1.0;
    self.sliderY.value = 0.0;
    self.sliderWidth.value = 1.0;
    self.sliderHeight.value = 1.0;
    self.sliderCorner.value = 1.0;
    self.sliderRefraction.value = 1.4;
    [self liquidSiriSliderChanged:self.sliderScale];
}

%new
- (void)liquidSiriSaveSettings:(UIButton *)btn {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionary];
    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.yourcompany.liquidsiri.prefs.plist"];
    if (!existing) existing = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.yourcompany.liquidsiri.prefs.plist"];
    if (existing) { [prefs addEntriesFromDictionary:existing]; }
    
    prefs[@"orbScale"] = @(self.sliderScale.value);
    prefs[@"yOffset"] = @(self.sliderY.value);
    prefs[@"customWidth"] = @(self.sliderWidth.value);
    prefs[@"customHeight"] = @(self.sliderHeight.value);
    prefs[@"customCorner"] = @(self.sliderCorner.value);
    prefs[@"customRefraction"] = @(self.sliderRefraction.value);
    
    [prefs writeToFile:@"/var/mobile/Library/Preferences/com.yourcompany.liquidsiri.prefs.plist" atomically:YES];
    [prefs writeToFile:@"/var/jb/var/mobile/Library/Preferences/com.yourcompany.liquidsiri.prefs.plist" atomically:YES];
    
    [btn setTitle:@"Saved!" forState:UIControlStateNormal];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [btn setTitle:@"Save Settings" forState:UIControlStateNormal];
    });
}

%new
- (void)liquidSiriSliderChanged:(UISlider *)slider {
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    if (safeTop == 0 && self.view.window) { safeTop = self.view.window.safeAreaInsets.top; }
    
    CGFloat baseW = 130.0;
    CGFloat baseH = 105.0;
    CGFloat physicalY = 31.0;
    
    if (safeTop >= 59.0) {
        baseW = 180.0;
        baseH = 148.0;
        physicalY = 9.0;
    } else if (safeTop > 44.0) {
        baseW = 144.0;
        baseH = 116.0;
        physicalY = 36.0;
    }
    
    CGFloat customScale = self.sliderScale.value;
    CGFloat customYOffset = self.sliderY.value;
    CGFloat customWidth = self.sliderWidth.value;
    CGFloat customHeight = self.sliderHeight.value;
    CGFloat customCorner = self.sliderCorner.value;
    CGFloat customRefraction = self.sliderRefraction.value;
    
    CGFloat finalW = baseW * customScale * customWidth;
    CGFloat finalH = baseH * customScale * customHeight;
    CGFloat finalY = physicalY + customYOffset;
    CGFloat physicalX = (screenSize.width - finalW) / 2.0;
    
    CGRect absoluteScreenFrame = CGRectMake(physicalX, finalY, finalW, finalH);
    CGRect orbFrame = [self.view convertRect:absoluteScreenFrame fromCoordinateSpace:[UIScreen mainScreen].coordinateSpace];
    
    self.glassOrbView.frame = orbFrame;
    CGFloat rawCorner = (finalH / 2.0) * customCorner;
    CGFloat maxCorner = MIN(finalW, finalH) / 2.0;
    self.glassOrbView.cornerRadius = MIN(rawCorner, maxCorner);
    self.glassOrbView.refractionScale = customRefraction;
    
    self.externalWhiteGlowView.frame = CGRectMake(orbFrame.origin.x + finalW * 0.15, orbFrame.origin.y + finalH - (35.0 * customScale), finalW * 0.7, 30.0 * customScale);
    UIBezierPath *newShadowPath = [UIBezierPath bezierPathWithOvalInRect:self.externalWhiteGlowView.bounds];
    self.externalWhiteGlowView.layer.shadowPath = newShadowPath.CGPath;
    
    self.glowLineView.frame = CGRectMake(0, 0, finalW, finalH);
    for (UIView *sub in self.glowLineView.subviews) {
        sub.frame = self.glowLineView.bounds;
    }
    
    for (CALayer *sub in [self.glassOrbView.layer.sublayers copy]) {
        if ([sub isKindOfClass:[CAShapeLayer class]] && CGColorEqualToColor(((CAShapeLayer *)sub).fillColor, [UIColor colorWithWhite:0.0 alpha:0.95].CGColor)) {
            CAShapeLayer *blackDomeLayer = (CAShapeLayer *)sub;
            blackDomeLayer.frame = CGRectMake(0, 0, finalW, finalH);
            
            UIBezierPath *domePath = [UIBezierPath bezierPath];
            [domePath moveToPoint:CGPointMake(0, 0)];
            [domePath addLineToPoint:CGPointMake(finalW, 0)];
            [domePath addLineToPoint:CGPointMake(finalW, finalH * 0.55)];
            [domePath addQuadCurveToPoint:CGPointMake(0, finalH * 0.55) controlPoint:CGPointMake(finalW / 2.0, finalH * 0.52)];
            [domePath closePath];
            blackDomeLayer.path = domePath.CGPath;
            
            CAGradientLayer *fadeMask = (CAGradientLayer *)blackDomeLayer.mask;
            if (fadeMask) {
                fadeMask.frame = blackDomeLayer.bounds;
            }
        }
    }
    
    [self.glassOrbView updateOrigin];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    
    // Hide default Siri blur effects so they don't darken the screen behind the orb
    self.view.backgroundColor = [UIColor clearColor];
    for (UIView *sub in self.view.subviews) {
        if (sub != self.glassOrbView && sub != self.glowLineView) {
            sub.alpha = 0.01; // DO NOT USE hidden=YES! iOS stops sending audio levels if hidden.
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[WaveManager shared] startRecording]; // NOP in SpringBoard
    
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    if (safeTop == 0 && self.view.window) { safeTop = self.view.window.safeAreaInsets.top; }
    
    CGFloat width = 130.0;
    CGFloat height = 105.0;
    CGFloat physicalY = 31.0;
    
    if (safeTop >= 59.0) {
        // iPhone 14 Pro / 15 Pro Max (Dynamic Island)
        // Wraps the black dome seamlessly around the island (made larger to fully hide it)
        width = 180.0;
        height = 148.0;
        physicalY = 9.0;
    } else if (safeTop > 44.0) {
        // iPhone 12 / 13
        width = 144.0;
        height = 116.0;
        physicalY = 36.0;
    }
    
    // Read user preferences directly so they apply immediately on Siri activation
    NSDictionary *prefsRootless = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.yourcompany.liquidsiri.prefs.plist"];
    NSDictionary *prefsMobile = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.yourcompany.liquidsiri.prefs.plist"];
    NSDictionary *prefs = prefsRootless ?: prefsMobile;
    
    CGFloat customYOffset = 0.0;
    CGFloat customScale = 1.0;
    CGFloat customWidth = 1.0;
    CGFloat customHeight = 1.0;
    CGFloat customCorner = 1.0;
    CGFloat customRefraction = 1.4;

    if (prefs) {
        if (prefs[@"yOffset"] != nil) customYOffset = [prefs[@"yOffset"] floatValue];
        if (prefs[@"orbScale"] != nil) customScale = [prefs[@"orbScale"] floatValue];
        if (prefs[@"customWidth"] != nil) customWidth = [prefs[@"customWidth"] floatValue];
        if (prefs[@"customHeight"] != nil) customHeight = [prefs[@"customHeight"] floatValue];
        if (prefs[@"customCorner"] != nil) customCorner = [prefs[@"customCorner"] floatValue];
        if (prefs[@"customRefraction"] != nil) customRefraction = [prefs[@"customRefraction"] floatValue];
    }
    
    width *= customScale * customWidth;
    height *= customScale * customHeight;
    physicalY += customYOffset;
    
    CGFloat physicalX = (screenSize.width - width)/2.0;
    CGRect absoluteScreenFrame = CGRectMake(physicalX, physicalY, width, height);
    CGRect orbFrame = [self.view convertRect:absoluteScreenFrame fromCoordinateSpace:[UIScreen mainScreen].coordinateSpace];
    
    self.glassOrbView.frame = orbFrame; 
    CGFloat rawCorner = (height / 2.0) * customCorner;
    CGFloat maxCorner = MIN(width, height) / 2.0;
    self.glassOrbView.cornerRadius = MIN(rawCorner, maxCorner);
    self.glassOrbView.refractionScale = customRefraction;
    
    // Update the external white glow to match the new scaled/shifted orbFrame
    self.externalWhiteGlowView.frame = CGRectMake(orbFrame.origin.x + width * 0.15, orbFrame.origin.y + height - (35.0 * customScale), width * 0.7, 30.0 * customScale);
    UIBezierPath *newShadowPath = [UIBezierPath bezierPathWithOvalInRect:self.externalWhiteGlowView.bounds];
    self.externalWhiteGlowView.layer.shadowPath = newShadowPath.CGPath;
    
    // Flawless Coordinate Math: Because the view is perfectly un-scaled and converted to local window coordinates,
    // LiquidGlassKit calculates the cardOrigin as the true absolute physical coordinate.
    // A wallpaperOrigin of (0,0) provides a 100% flawless 1:1 physical screen match.
    // The user requested the reflection inside to be a bit lower.
    // To move the reflection lower, we sample higher on the screenshot (positive Y).
    CGFloat reflectionYOffset = 0.0;
    
    self.glassOrbView.wallpaperOrigin = CGPointMake(0, reflectionYOffset);
    [self.glassOrbView updateOrigin]; // Force update now that it's physically in the window
    
    // Clean up to strictly prevent any double layers
    for (CALayer *sub in [self.glassOrbView.layer.sublayers copy]) {
        if ([sub isKindOfClass:[CAGradientLayer class]]) {
            [sub removeFromSuperlayer];
        }
    }
    
    // Add the solid black curved dome overlay directly on top of the glass
    // The user requested a heavy curvature for the black glass separation line.
    // We use a bezier path that comes down at the edges and arcs heavily UP in the center.
    CAShapeLayer *blackDomeLayer = [CAShapeLayer layer];
    blackDomeLayer.frame = CGRectMake(0, 0, width, height);
    blackDomeLayer.fillColor = [UIColor colorWithWhite:0.0 alpha:0.95].CGColor;
    
    UIBezierPath *domePath = [UIBezierPath bezierPath];
    [domePath moveToPoint:CGPointMake(0, 0)];
    [domePath addLineToPoint:CGPointMake(width, 0)];
    
    // Drop down to 55% height on the right edge
    [domePath addLineToPoint:CGPointMake(width, height * 0.55)];
    
    // A tiny, tiny bit of curvature: landing at 55% with the center control point at 52%
    [domePath addQuadCurveToPoint:CGPointMake(0, height * 0.55) controlPoint:CGPointMake(width / 2.0, height * 0.52)];
    
    [domePath closePath];
    blackDomeLayer.path = domePath.CGPath;
    
    // Soften the boundary line so it blends like glass
    blackDomeLayer.shadowColor = [UIColor blackColor].CGColor;
    blackDomeLayer.shadowOffset = CGSizeZero;
    blackDomeLayer.shadowRadius = 10.0;
    blackDomeLayer.shadowOpacity = 1.0;
    
    // The user requested fading on BOTH the bottom and a tiny bit on the sides.
    // A radial gradient from the top-center flawlessly achieves this, fading outwards in all directions.
    CAGradientLayer *fadeMask = [CAGradientLayer layer];
    fadeMask.frame = blackDomeLayer.bounds;
    fadeMask.type = kCAGradientLayerRadial;
    
    fadeMask.colors = @[(id)[UIColor blackColor].CGColor,
                        (id)[UIColor blackColor].CGColor,
                        (id)[UIColor clearColor].CGColor];
    
    // Fade starts at 65% of the radius (a bit more fading) and goes to clear at the edges.
    fadeMask.locations = @[@0.0, @0.65, @1.0];
    
    // Start at top center
    fadeMask.startPoint = CGPointMake(0.5, 0.0);
    // End point defines the elliptical radius. 
    // We mathematically calculated the X coordinate to be 1.24.
    // This pushes the solid black area to exactly 98% of the orb's width, leaving precisely 2% fading on the extreme edges.
    // The Y coordinate stays at 0.55 to match the 55% depth and keep the bottom fade perfectly intact.
    fadeMask.endPoint = CGPointMake(1.24, 0.55);
    
    blackDomeLayer.mask = fadeMask;
    
    // Insert the black dome so it sits precisely underneath the glowing Siri wave's layer, 
    // but ABOVE the UIVisualEffectView's backdrop layer!
    [self.glassOrbView.layer insertSublayer:blackDomeLayer below:self.glowLineView.layer];
    
    // Start hidden and tucked up inside the Notch
    self.glassOrbView.hidden = YES;
    self.glassOrbView.alpha = 0.0;
    
    if (![self hasCapturedBackdrop]) {
        // Increase delay to 0.45s to guarantee iOS has finished the downsampled transition and resolved the full high-res hardware buffer
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            
            UIImage *rawWallpaperImage = _UICreateScreenUIImage();
            if (rawWallpaperImage) {
                // FLAWLESS NORMALIZATION:
                // 1. Sometimes iOS returns a downsampled buffer (e.g. 390x844 pixels instead of 1170x2532) to save memory during transitions.
                // 2. Sometimes iOS returns a raw landscape buffer (e.g. 2532x1170) natively from the camera sensor.
                // Both of these cause LiquidGlassKit to mathematically zoom/squish the shader!
                // We MUST forcefully redraw it into a context that perfectly matches the absolute physical pixels of the portrait screen.
                
                CGFloat scale = [UIScreen mainScreen].scale;
                CGSize expectedPixelSize = CGSizeMake(screenSize.width * scale, screenSize.height * scale); // e.g. 1170x2532
                
                CGImageRef cgImage = rawWallpaperImage.CGImage;
                size_t cgWidth = CGImageGetWidth(cgImage);
                size_t cgHeight = CGImageGetHeight(cgImage);
                
                BOOL needsRotation = (cgWidth > cgHeight) && (expectedPixelSize.height > expectedPixelSize.width);
                BOOL needsScaling = (cgWidth != expectedPixelSize.width) || (cgHeight != expectedPixelSize.height);
                
                if (needsRotation || needsScaling) {
                    UIGraphicsBeginImageContextWithOptions(expectedPixelSize, NO, 1.0);
                    CGContextRef context = UIGraphicsGetCurrentContext();
                    
                    if (needsRotation) {
                        CGContextTranslateCTM(context, expectedPixelSize.width/2.0, expectedPixelSize.height/2.0);
                        CGContextRotateCTM(context, M_PI_2);
                        // Draw rotated, scaling it to fit the swapped dimensions
                        CGContextDrawImage(context, CGRectMake(-expectedPixelSize.height/2.0, -expectedPixelSize.width/2.0, expectedPixelSize.height, expectedPixelSize.width), cgImage);
                    } else {
                        // Just draw scaled
                        CGContextDrawImage(context, CGRectMake(0, 0, expectedPixelSize.width, expectedPixelSize.height), cgImage);
                    }
                    
                    // We must flip it vertically because CGContextDrawImage renders upside down
                    UIImage *contextImage = UIGraphicsGetImageFromCurrentImageContext();
                    UIGraphicsEndImageContext();
                    
                    // Flip vertically
                    UIGraphicsBeginImageContextWithOptions(expectedPixelSize, NO, 1.0);
                    context = UIGraphicsGetCurrentContext();
                    CGContextTranslateCTM(context, 0, expectedPixelSize.height);
                    CGContextScaleCTM(context, 1.0, -1.0);
                    [contextImage drawInRect:CGRectMake(0, 0, expectedPixelSize.width, expectedPixelSize.height)];
                    rawWallpaperImage = UIGraphicsGetImageFromCurrentImageContext();
                    UIGraphicsEndImageContext();
                } else {
                    // It's perfectly fine
                    rawWallpaperImage = [UIImage imageWithCGImage:cgImage scale:1.0 orientation:UIImageOrientationUp];
                }
                
                [self setCapturedWallpaper:rawWallpaperImage];
                self.glassOrbView.wallpaperImage = rawWallpaperImage;
            }
            
            [self setHasCapturedBackdrop:YES];
            
            // Pop out animation
            self.glassOrbView.hidden = NO;
            [UIView animateWithDuration:0.6 delay:0.0 usingSpringWithDamping:0.7 initialSpringVelocity:0.6 options:UIViewAnimationOptionCurveEaseOut animations:^{
                self.glassOrbView.transform = CGAffineTransformIdentity;
                self.glassOrbView.alpha = 1.0;
                self.externalWhiteGlowView.alpha = 1.0;
            } completion:^(BOOL finished) {
                // After popping in, start a gentle, infinite breathing animation to make the liquid feel alive
                CABasicAnimation *breatheAnim = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
                breatheAnim.fromValue = @(1.0);
                breatheAnim.toValue = @(1.03);
                breatheAnim.duration = 1.2; // Faster, energetic breaths
                breatheAnim.autoreverses = YES;
                breatheAnim.repeatCount = HUGE_VALF; // Infinite
                breatheAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
                [self.glassOrbView.layer addAnimation:breatheAnim forKey:@"orbBreathing"];
            }];
        });
    } else {
        // Already captured, just animate in
        self.glassOrbView.wallpaperImage = [self capturedWallpaper];
        self.glassOrbView.hidden = NO;
        [UIView animateWithDuration:0.6 delay:0.0 usingSpringWithDamping:0.7 initialSpringVelocity:0.6 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.glassOrbView.transform = CGAffineTransformIdentity;
            self.glassOrbView.alpha = 1.0;
            self.externalWhiteGlowView.alpha = 1.0;
        } completion:^(BOOL finished) {
            CABasicAnimation *breatheAnim = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
            breatheAnim.fromValue = @(1.0);
            breatheAnim.toValue = @(1.03);
            breatheAnim.duration = 1.2; // Faster, energetic breaths
            breatheAnim.autoreverses = YES;
            breatheAnim.repeatCount = HUGE_VALF; // Infinite
            breatheAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [self.glassOrbView.layer addAnimation:breatheAnim forKey:@"orbBreathing"];
        }];
    }
    
    // Reposition wave line with much more vertical breathing room
    self.glowLineView.frame = CGRectMake(0, 0, width, height);
    
    // Completely remove old wave views to prevent stacking and off-center bugs when sliders change
    for (UIView *subview in self.glowLineView.subviews) {
        [subview removeFromSuperview];
    }
    
    UIView *swiftWave = [[WaveManager shared] createWaveViewWithFrame:self.glowLineView.bounds];
    swiftWave.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [WaveManager shared].power = 0.5; // Stronger resting state
    [self.glowLineView addSubview:swiftWave];
}


- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    [UIView animateWithDuration:0.35 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.glassOrbView.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0, -50), CGAffineTransformMakeScale(0.6, 0.6));
        self.glassOrbView.alpha = 0.0;
        self.externalWhiteGlowView.alpha = 0.0;
    } completion:nil];
}

%end

#import <notify.h>
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>

// This safely bridges the audio level to SpringBoard via Darwin Notification State
static int notifyToken = 0;

static void sendPowerToSpringBoard(float level) {
    [[WaveManager shared] updateTargetPower:@(level)];
}

// -----------------------------------------------------------------------------
// NATIVE SIRI AUDIO STEALING
// Siri actually PULLS audio levels via a delegate at 60fps rather than pushing it.
// We attach a display link to the native views to ask
// Removed duplicate interface declarations for SUICFlamesView because Logos generates them automatically

// Removed duplicate interface declarations for SUICFlamesView because Logos generates them automatically



%hook AFUISiriSession
- (void)setState:(long long)state {
    %orig;
    if (state == 3) globalSiriState = 3;
    else if (state == 1) globalSiriState = 1;
}
%end

%hook VSSpeechSynthesizer
- (id)startSpeakingRequest:(id)arg1 {
    globalSiriState = 3;
    return %orig;
}
- (id)stopSpeakingRequest:(id)arg1 {
    globalSiriState = 1;
    return %orig;
}
- (id)stopSpeakingAtNextBoundary:(long long)arg1 {
    globalSiriState = 1;
    return %orig;
}
%end

%hook SUICFlamesView

- (void)setState:(NSInteger)state {
    %orig;
    globalSiriState = state;
}

- (void)transitionToState:(NSInteger)state animated:(BOOL)animated {
    %orig;
    globalSiriState = state;
}

- (void)didMoveToWindow {
    %orig;
    UIView *viewSelf = (UIView *)self;
    if (viewSelf.window) {
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(liquidSiriPollAudio:)];
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        objc_setAssociatedObject(self, @selector(liquidSiriPollAudio:), link, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        CADisplayLink *link = objc_getAssociatedObject(self, @selector(liquidSiriPollAudio:));
        [link invalidate];
    }
}

%new
- (void)liquidSiriPollAudio:(CADisplayLink *)link {
    id delegate = nil;
    id objSelf = (id)self;
    @try {
        if ([objSelf respondsToSelector:@selector(flamesDelegate)]) {
            delegate = [objSelf valueForKey:@"flamesDelegate"];
        } else if ([objSelf respondsToSelector:@selector(delegate)]) {
            delegate = [objSelf valueForKey:@"delegate"];
        }
    } @catch (NSException *e) {}

    if (delegate && [delegate respondsToSelector:@selector(audioLevelForFlamesView:)]) {
        float level = ((float (*)(id, SEL, id))objc_msgSend)(delegate, @selector(audioLevelForFlamesView:), self);
        
        @try {
            BOOL speaking = NO;
            
            // Check global state
            if (globalSiriState == 3) {
                speaking = YES;
            }
            
            // Check AVAudioSession mode (Siri uses VoicePrompt when speaking)
            @try {
                id audioSession = [NSClassFromString(@"AVAudioSession") sharedInstance];
                if (audioSession) {
                    NSString *audioMode = [audioSession valueForKey:@"mode"];
                    if ([audioMode isEqualToString:@"VoicePrompt"]) {
                        speaking = YES;
                    }
                }
            } @catch (NSException *e) {}
            
            // Check delegate
            if ([delegate respondsToSelector:@selector(isSpeaking)]) {
                if ([[delegate valueForKey:@"isSpeaking"] boolValue]) speaking = YES;
            }
            
            // Check inner flamesView
            id checkView = objSelf;
            if ([objSelf respondsToSelector:@selector(flamesView)]) {
                checkView = [objSelf valueForKey:@"flamesView"];
            }
            if ([checkView respondsToSelector:@selector(state)]) {
                NSInteger state = [[checkView valueForKey:@"state"] integerValue];
                if (state == 3) {
                    speaking = YES;
                }
            }
            
            if (speaking) {
                level = 0.0;
            }
        } @catch (NSException *e) {}
        
        sendPowerToSpringBoard(level);
    }
}

%end

%hook SiriUIFlamesView

- (void)setState:(NSInteger)state {
    %orig;
    globalSiriState = state;
}

- (void)didMoveToWindow {
    %orig;
    UIView *viewSelf = (UIView *)self;
    if (viewSelf.window) {
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(liquidSiriPollAudio:)];
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        objc_setAssociatedObject(self, @selector(liquidSiriPollAudio:), link, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        CADisplayLink *link = objc_getAssociatedObject(self, @selector(liquidSiriPollAudio:));
        [link invalidate];
    }
}

%new
- (void)liquidSiriPollAudio:(CADisplayLink *)link {
    id delegate = nil;
    id objSelf = (id)self;
    @try {
        if ([objSelf respondsToSelector:@selector(flamesDelegate)]) {
            delegate = [objSelf valueForKey:@"flamesDelegate"];
        } else if ([objSelf respondsToSelector:@selector(delegate)]) {
            delegate = [objSelf valueForKey:@"delegate"];
        }
    } @catch (NSException *e) {}

    if (delegate && [delegate respondsToSelector:@selector(audioLevelForFlamesView:)]) {
        float level = ((float (*)(id, SEL, id))objc_msgSend)(delegate, @selector(audioLevelForFlamesView:), self);
        
        @try {
            BOOL speaking = NO;
            
            // Check global state
            if (globalSiriState == 3) {
                speaking = YES;
            }
            
            // Check AVAudioSession mode (Siri uses VoicePrompt when speaking)
            @try {
                id audioSession = [NSClassFromString(@"AVAudioSession") sharedInstance];
                if (audioSession) {
                    NSString *audioMode = [audioSession valueForKey:@"mode"];
                    if ([audioMode isEqualToString:@"VoicePrompt"]) {
                        speaking = YES;
                    }
                }
            } @catch (NSException *e) {}
            
            // Check delegate
            if ([delegate respondsToSelector:@selector(isSpeaking)]) {
                if ([[delegate valueForKey:@"isSpeaking"] boolValue]) speaking = YES;
            }
            
            // Check inner flamesView
            id checkView = objSelf;
            if ([objSelf respondsToSelector:@selector(flamesView)]) {
                checkView = [objSelf valueForKey:@"flamesView"];
            }
            if ([checkView respondsToSelector:@selector(state)]) {
                NSInteger state = [[checkView valueForKey:@"state"] integerValue];
                if (state == 3) {
                    speaking = YES;
                }
            }
            
            if (speaking) {
                level = 0.0;
            }
        } @catch (NSException *e) {}
        
        sendPowerToSpringBoard(level);
    }
}

%end

%hook SiriUIBackgroundBlurViewController

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [[WaveManager shared] stopRecording];
    sendPowerToSpringBoard(0.0);
}

%end
%ctor {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.yourcompany.liquidsiri.prefs.plist"];
    BOOL isEnabled = YES;
    if (prefs && prefs[@"enabled"] != nil) {
        isEnabled = [prefs[@"enabled"] boolValue];
    } else {
        NSDictionary *prefsRootless = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.yourcompany.liquidsiri.prefs.plist"];
        if (prefsRootless && prefsRootless[@"enabled"] != nil) {
            isEnabled = [prefsRootless[@"enabled"] boolValue];
        }
    }
    if (isEnabled) {
        %init;
    }
}
