#import "LGGlassRenderer.h"
#import "../Runtime/LGLiquidGlassRuntime.h"

void LGEnsureSharedGlassPipelinesReady(void) {
    LGPrewarmPipelines();
}

@implementation LGSharedGlassView

@dynamic cornerRadius;
@dynamic bezelWidth;
@dynamic glassThickness;
@dynamic refractionScale;
@dynamic refractiveIndex;
@dynamic specularOpacity;
@dynamic blur;

- (instancetype)initWithFrame:(CGRect)frame sourceImage:(UIImage *)image sourceOrigin:(CGPoint)origin {
    LGEnsureSharedGlassPipelinesReady();
    self = [super initWithFrame:frame wallpaper:image wallpaperOrigin:origin];
    if (!self) return nil;
    self.updateGroup = LGUpdateGroupAll;
    return self;
}

- (UIImage *)sourceImage {
    return self.wallpaperImage;
}

- (void)setSourceImage:(UIImage *)image {
    self.wallpaperImage = image;
}

- (CGPoint)sourceOrigin {
    return self.wallpaperOrigin;
}

- (void)setSourceOrigin:(CGPoint)origin {
    self.wallpaperOrigin = origin;
}

- (CGFloat)sourceScale {
    return self.wallpaperScale;
}

- (void)setSourceScale:(CGFloat)scale {
    self.wallpaperScale = scale;
}

- (BOOL)releasesSourceAfterUpload {
    return self.releasesWallpaperAfterUpload;
}

- (void)setReleasesSourceAfterUpload:(BOOL)releases {
    self.releasesWallpaperAfterUpload = releases;
}

@end
