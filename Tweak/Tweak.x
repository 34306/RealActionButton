#import "ABMCClickManager.h"
#import "ABMCActionExecutor.h"
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL longPressActive = NO;

// Calibration state
static BOOL calibrationMode = NO;
static NSTimeInterval calibrationFirstPress = 0;

static void disableArbiterMultiClick(id buttonInstance) {
    Ivar arbiterIvar = class_getInstanceVariable(object_getClass(buttonInstance), "_buttonArbiter");
    if (!arbiterIvar) return;
    id arbiter = object_getIvar(buttonInstance, arbiterIvar);
    if (!arbiter) return;

    SEL setMaxSel = NSSelectorFromString(@"setMaximumRepeatedPressCount:");
    if ([arbiter respondsToSelector:setMaxSel]) {
        ((void (*)(id, SEL, unsigned long long))objc_msgSend)(arbiter, setMaxSel, 0);
    }
}

static void handleCalibrationPress(void) {
    NSTimeInterval now = [[NSProcessInfo processInfo] systemUptime];

    if (calibrationFirstPress == 0) {
        // First press — record and wait
        calibrationFirstPress = now;
        return;
    }

    // Second press — calculate interval
    double interval = now - calibrationFirstPress;
    calibrationFirstPress = 0;
    calibrationMode = NO;

    // Add 0.3s buffer so the user has some margin
    double timeout = interval + 0.3;
    if (timeout < 0.3) timeout = 0.3;
    if (timeout > 3.0) timeout = 3.0;

    // Save to preferences
    CFPreferencesSetAppValue(CFSTR("clickTimeout"),
                             (__bridge CFPropertyListRef)@(timeout),
                             CFSTR("com.huynguyen.actionbuttonmulticlick"));
    CFPreferencesAppSynchronize(CFSTR("com.huynguyen.actionbuttonmulticlick"));

    // Update the click manager
    [ABMCClickManager sharedManager].clickTimeout = timeout;

    // Notify preferences UI to refresh
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged"),
                                         NULL, NULL, YES);

    // Post calibration result so Settings can show it
    NSString *resultStr = [NSString stringWithFormat:@"%.2f", interval];
    CFPreferencesSetAppValue(CFSTR("lastCalibrationInterval"),
                             (__bridge CFPropertyListRef)resultStr,
                             CFSTR("com.huynguyen.actionbuttonmulticlick"));
    CFPreferencesSetAppValue(CFSTR("lastCalibrationTimeout"),
                             (__bridge CFPropertyListRef)@(timeout),
                             CFSTR("com.huynguyen.actionbuttonmulticlick"));
    CFPreferencesAppSynchronize(CFSTR("com.huynguyen.actionbuttonmulticlick"));

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.huynguyen.actionbuttonmulticlick/calibrationDone"),
                                         NULL, NULL, YES);
}

static void startCalibration(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    calibrationMode = YES;
    calibrationFirstPress = 0;
    [[ABMCClickManager sharedManager] cancelPendingClicks];
}

static void prefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [[ABMCActionExecutor sharedExecutor] reloadPreferences];

    CFPreferencesAppSynchronize(CFSTR("com.huynguyen.actionbuttonmulticlick"));
    CFPropertyListRef val = CFPreferencesCopyAppValue(CFSTR("clickTimeout"), CFSTR("com.huynguyen.actionbuttonmulticlick"));
    if (val) {
        double timeout = [(__bridge NSNumber *)val doubleValue];
        [ABMCClickManager sharedManager].clickTimeout = timeout;
        CFRelease(val);
    }
}

// iOS 26+
%hook SBActionHardwareButton

- (void)_configureButtonArbiter {
    %orig;
    disableArbiterMultiClick(self);
}

- (void)performActionsForButtonDown:(id)event {
    if (calibrationMode) return;
    if (ABMCPerformingDefaultAction) { %orig; return; }
    [ABMCActionExecutor sharedExecutor].buttonInstance = self;
    [ABMCActionExecutor sharedExecutor].lastDownEvent = event;
}

- (void)performActionsForButtonUp:(id)event {
    if (calibrationMode) { handleCalibrationPress(); return; }
    if (ABMCPerformingDefaultAction) { %orig; return; }
    if (longPressActive) {
        longPressActive = NO;
        %orig;
        return;
    }

    [[ABMCClickManager sharedManager] registerClick];
}

- (void)performActionsForButtonLongPress:(id)event {
    if (calibrationMode) return;
    if (ABMCPerformingDefaultAction) { %orig; return; }
    longPressActive = YES;
    [[ABMCClickManager sharedManager] cancelPendingClicks];
    ABMCPerformingDefaultAction = YES;
    ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(performActionsForButtonDown:), [ABMCActionExecutor sharedExecutor].lastDownEvent);
    %orig;
    ABMCPerformingDefaultAction = NO;
}

%end

// iOS 17-18
%hook SBRingerHardwareButton

- (void)_configureButtonArbiter {
    %orig;
    disableArbiterMultiClick(self);
}

- (void)performActionsForButtonDown:(id)event {
    if (calibrationMode) return;
    if (ABMCPerformingDefaultAction) { %orig; return; }
    [ABMCActionExecutor sharedExecutor].buttonInstance = self;
    [ABMCActionExecutor sharedExecutor].lastDownEvent = event;
}

- (void)performActionsForButtonUp:(id)event {
    if (calibrationMode) { handleCalibrationPress(); return; }
    if (ABMCPerformingDefaultAction) { %orig; return; }
    if (longPressActive) {
        longPressActive = NO;
        %orig;
        return;
    }

    [[ABMCClickManager sharedManager] registerClick];
}

- (void)performActionsForButtonLongPress:(id)event {
    if (calibrationMode) return;
    if (ABMCPerformingDefaultAction) { %orig; return; }
    longPressActive = YES;
    [[ABMCClickManager sharedManager] cancelPendingClicks];
    ABMCPerformingDefaultAction = YES;
    ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(performActionsForButtonDown:), [ABMCActionExecutor sharedExecutor].lastDownEvent);
    %orig;
    ABMCPerformingDefaultAction = NO;
}

%end

%ctor {
    [ABMCClickManager sharedManager].clickCallback = ^(ABMCClickType clickType) {
        [[ABMCActionExecutor sharedExecutor] executeActionForClickType:clickType];
    };

    prefsChanged(NULL, NULL, NULL, NULL, NULL);

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        prefsChanged,
        CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        startCalibration,
        CFSTR("com.huynguyen.actionbuttonmulticlick/startCalibration"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}
