#import "ABMCPreferences.h"
#import <Preferences/PSSpecifier.h>

#define PREFS_DOMAIN @"com.huynguyen.actionbuttonmulticlick"
#define PREFS_NOTIFICATION @"com.huynguyen.actionbuttonmulticlick/prefsChanged"

static NSString *titleForActionID(NSString *actionID) {
    if (!actionID || [actionID isEqualToString:@"none"]) return @"Do Nothing";
    if ([actionID isEqualToString:@"default"]) return @"System Default";
    if ([actionID isEqualToString:@"flashlight"]) return @"Toggle Flashlight";
    if ([actionID isEqualToString:@"camera"]) return @"Open Camera";
    if ([actionID isEqualToString:@"silent"]) return @"Toggle Silent Mode";
    if ([actionID isEqualToString:@"screenshot"]) return @"Take Screenshot";
    if ([actionID isEqualToString:@"lock"]) return @"Lock Device";
    if ([actionID isEqualToString:@"respring"]) return @"Respring";
    if ([actionID hasPrefix:@"app:"]) return [NSString stringWithFormat:@"App: %@", [actionID substringFromIndex:4]];
    if ([actionID hasPrefix:@"shortcut:"]) return [NSString stringWithFormat:@"Shortcut: %@", [actionID substringFromIndex:9]];
    return actionID;
}

static void calibrationDoneCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    ABMCPreferences *self = (__bridge ABMCPreferences *)observer;
    [self calibrationDidFinish];
}

@implementation ABMCPreferences {
    BOOL _waitingForCalibration;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        // Click Actions group
        PSSpecifier *group1 = [PSSpecifier groupSpecifierWithName:@"Click Actions"];
        [group1 setProperty:@"Configure what each click type does. Long press is unchanged." forKey:@"footerText"];
        [specs addObject:group1];

        // Single Click
        PSSpecifier *single = [PSSpecifier preferenceSpecifierNamed:@"Single Click"
                                                             target:self
                                                                set:NULL
                                                                get:NULL
                                                             detail:NSClassFromString(@"ABMCActionListController")
                                                               cell:PSLinkCell
                                                               edit:Nil];
        [single setProperty:@"singleClickAction" forKey:@"key"];
        [single setProperty:@"default" forKey:@"default"];
        [single setProperty:PREFS_DOMAIN forKey:@"defaults"];
        [specs addObject:single];

        // Double Click
        PSSpecifier *dbl = [PSSpecifier preferenceSpecifierNamed:@"Double Click"
                                                          target:self
                                                             set:NULL
                                                             get:NULL
                                                          detail:NSClassFromString(@"ABMCActionListController")
                                                            cell:PSLinkCell
                                                            edit:Nil];
        [dbl setProperty:@"doubleClickAction" forKey:@"key"];
        [dbl setProperty:@"none" forKey:@"default"];
        [dbl setProperty:PREFS_DOMAIN forKey:@"defaults"];
        [specs addObject:dbl];

        // Timing group
        PSSpecifier *group2 = [PSSpecifier groupSpecifierWithName:@"Timing"];
        [group2 setProperty:@"How long to wait for a second click before triggering single click. Tap Calibrate to auto-detect your natural double-click speed." forKey:@"footerText"];
        [specs addObject:group2];

        // Click Timeout slider
        PSSpecifier *timeout = [PSSpecifier preferenceSpecifierNamed:@"Click Timeout"
                                                              target:self
                                                                 set:@selector(setPreferenceValue:specifier:)
                                                                 get:@selector(readPreferenceValue:)
                                                              detail:Nil
                                                                cell:PSSliderCell
                                                                edit:Nil];
        [timeout setProperty:@"clickTimeout" forKey:@"key"];
        [timeout setProperty:@0.5 forKey:@"min"];
        [timeout setProperty:@2.0 forKey:@"max"];
        [timeout setProperty:@1.5 forKey:@"default"];
        [timeout setProperty:PREFS_DOMAIN forKey:@"defaults"];
        [timeout setProperty:PREFS_NOTIFICATION forKey:@"PostNotification"];
        [timeout setProperty:@YES forKey:@"showValue"];
        [specs addObject:timeout];

        // Calibrate button
        PSSpecifier *calibrate = [PSSpecifier preferenceSpecifierNamed:@"Calibrate Double Click"
                                                               target:self
                                                                  set:NULL
                                                                  get:NULL
                                                               detail:Nil
                                                                 cell:PSButtonCell
                                                                 edit:Nil];
        calibrate->action = @selector(startCalibration);
        [specs addObject:calibrate];

        _specifiers = specs;
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        calibrationDoneCallback,
        CFSTR("com.huynguyen.actionbuttonmulticlick/calibrationDone"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );

    [self reload];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    CFNotificationCenterRemoveObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        CFSTR("com.huynguyen.actionbuttonmulticlick/calibrationDone"),
        NULL
    );
}

- (void)startCalibration {
    _waitingForCalibration = YES;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Calibrate"
                                                                  message:@"Press the Action Button twice at your natural double-click speed.\n\nThe timeout will be adjusted automatically."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        self->_waitingForCalibration = NO;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Ready" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        // Tell SpringBoard to enter calibration mode
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFSTR("com.huynguyen.actionbuttonmulticlick/startCalibration"),
                                             NULL, NULL, YES);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)calibrationDidFinish {
    if (!_waitingForCalibration) return;
    _waitingForCalibration = NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        // Read the result
        CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);

        CFPropertyListRef intervalRef = CFPreferencesCopyAppValue(CFSTR("lastCalibrationInterval"), (__bridge CFStringRef)PREFS_DOMAIN);
        CFPropertyListRef timeoutRef = CFPreferencesCopyAppValue(CFSTR("lastCalibrationTimeout"), (__bridge CFStringRef)PREFS_DOMAIN);

        NSString *intervalStr = intervalRef ? (__bridge_transfer NSString *)intervalRef : @"?";
        NSNumber *timeoutNum = timeoutRef ? (__bridge_transfer NSNumber *)timeoutRef : @(1.5);

        NSString *msg = [NSString stringWithFormat:@"Your double-click interval: %@s\nTimeout set to: %.2fs (interval + 0.3s buffer)", intervalStr, timeoutNum.doubleValue];

        UIAlertController *result = [UIAlertController alertControllerWithTitle:@"Calibration Done"
                                                                       message:msg
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [result addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:result animated:YES completion:nil];

        // Refresh the slider
        [self reloadSpecifiers];
    });
}

- (void)reloadSpecifiers {
    [super reloadSpecifiers];
    for (PSSpecifier *spec in _specifiers) {
        NSString *key = [spec propertyForKey:@"key"];
        if ([key hasSuffix:@"Action"]) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
            CFStringRef val = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)PREFS_DOMAIN);
            NSString *actionID = val ? (__bridge_transfer NSString *)val : [spec propertyForKey:@"default"];
            [spec setProperty:titleForActionID(actionID) forKey:@"cellValue"];
        }
    }
}

@end
