#pragma once

#import "../LiquidGlass.h"

void LGEnsureSharedGlassPipelinesReady(void);

@interface LGSharedGlassView : LiquidGlassView

@property (nonatomic, strong) UIImage *sourceImage;
@property (nonatomic, assign) CGPoint sourceOrigin;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) CGFloat bezelWidth;
@property (nonatomic, assign) CGFloat glassThickness;
@property (nonatomic, assign) CGFloat refractionScale;
@property (nonatomic, assign) CGFloat refractiveIndex;
@property (nonatomic, assign) CGFloat specularOpacity;
@property (nonatomic, assign) CGFloat blur;
@property (nonatomic, assign) CGFloat sourceScale;
@property (nonatomic, assign) BOOL releasesSourceAfterUpload;

- (instancetype)initWithFrame:(CGRect)frame sourceImage:(UIImage *)image sourceOrigin:(CGPoint)origin;

@end
