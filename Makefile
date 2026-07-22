TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiquidSiri

LiquidSiri_FILES = Tweak.x SwiftUIWave/Models/SiriWave.swift SwiftUIWave/Views/SupportLine.swift SwiftUIWave/Views/WaveView.swift SwiftUIWave/Views/SiriWaveView.swift SwiftUIWave/Views/SiriMetalView.swift SwiftUIWave/WaveManager.swift Shared/LGSharedSupport.m Shared/LGHookSupport.m Shared/LGBannerCaptureSupport.m Shared/LGMetalShaderSource.m Shared/LGGlassRenderer.m Shared/LGBackButtonSupport.m Shared/LGRWBSupport.m Runtime/LGLiquidGlassRuntime.m Runtime/LGSnapshotCaptureSupport.m Runtime/LGChatGPTBrain.x
LiquidSiri_SWIFTFLAGS = -swift-version 5
LiquidSiri_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
LiquidSiri_FRAMEWORKS = UIKit Foundation SwiftUI AVFoundation Accelerate AudioToolbox MetalKit

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += liquidsiriprefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	@echo "Compiling Metal shaders for SwiftUI ShaderLibrary..."
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/Application Support/LiquidSiri.bundle"
	@xcrun -sdk iphoneos metal -c Shared/SiriWave.metal -o "$(THEOS_STAGING_DIR)/Library/Application Support/LiquidSiri.bundle/SiriWave.air"
	@xcrun -sdk iphoneos metallib "$(THEOS_STAGING_DIR)/Library/Application Support/LiquidSiri.bundle/SiriWave.air" -o "$(THEOS_STAGING_DIR)/Library/Application Support/LiquidSiri.bundle/default.metallib"
	@rm "$(THEOS_STAGING_DIR)/Library/Application Support/LiquidSiri.bundle/SiriWave.air"
