TARGET := iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = liquidsiriprefs

liquidsiriprefs_FILES = LSPRootListController.m
liquidsiriprefs_FRAMEWORKS = UIKit
liquidsiriprefs_LDFLAGS = $(THEOS_PROJECT_DIR)/liquidsiriprefs/libPreferences.tbd
liquidsiriprefs_INSTALL_PATH = /Library/PreferenceBundles
liquidsiriprefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
