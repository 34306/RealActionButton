TARGET := iphone:clang:latest
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME = rootless
export ARCHS = arm64 arm64e

TWEAK_NAME = RealActionButton
$(TWEAK_NAME)_FILES = Tweak.x ABMCClickManager.m ABMCActionExecutor.m
$(TWEAK_NAME)_CFLAGS = -fobjc-arc
$(TWEAK_NAME)_FRAMEWORKS = UIKit AudioToolbox AVFoundation

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
