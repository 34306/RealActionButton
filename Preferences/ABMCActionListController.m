#import "ABMCActionListController.h"
#import <Preferences/PSSpecifier.h>

#define PREFS_DOMAIN @"com.huynguyen.actionbuttonmulticlick"
#define PREFS_NOTIFICATION @"com.huynguyen.actionbuttonmulticlick/prefsChanged"

typedef struct {
    NSString *actionID;
    NSString *title;
} ABMCAction;

static const ABMCAction kBuiltInActions[] = {
    { @"default",    @"System Default" },
    { @"flashlight", @"Toggle Flashlight" },
    { @"camera",     @"Open Camera" },
    { @"silent",     @"Toggle Silent Mode" },
    { @"screenshot", @"Take Screenshot" },
    { @"lock",       @"Lock Device" },
    { @"respring",   @"Respring" },
    { @"none",       @"Do Nothing" },
};

@implementation ABMCActionListController {
    NSString *_prefKey;
    NSString *_currentValue;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    PSSpecifier *parentSpecifier = [self specifier];
    _prefKey = [parentSpecifier propertyForKey:@"key"];
    NSString *defaultVal = [parentSpecifier propertyForKey:@"default"] ?: @"none";

    CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
    CFStringRef val = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_prefKey, (__bridge CFStringRef)PREFS_DOMAIN);
    _currentValue = val ? (__bridge_transfer NSString *)val : defaultVal;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        // Built-in actions group
        PSSpecifier *group1 = [PSSpecifier groupSpecifierWithName:@"Actions"];
        [specs addObject:group1];

        NSUInteger count = sizeof(kBuiltInActions) / sizeof(kBuiltInActions[0]);
        for (NSUInteger i = 0; i < count; i++) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:kBuiltInActions[i].title
                                                              target:self
                                                                 set:NULL
                                                                 get:NULL
                                                              detail:Nil
                                                                cell:PSStaticTextCell
                                                                edit:Nil];
            [spec setProperty:kBuiltInActions[i].actionID forKey:@"actionID"];
            spec->action = @selector(selectAction:);
            [specs addObject:spec];
        }

        // Custom actions group
        PSSpecifier *group2 = [PSSpecifier groupSpecifierWithName:@"Custom"];
        [group2 setProperty:@"Open a specific app by bundle ID or run a Siri Shortcut by name." forKey:@"footerText"];
        [specs addObject:group2];

        PSSpecifier *openApp = [PSSpecifier preferenceSpecifierNamed:@"Open App..."
                                                             target:self
                                                                set:NULL
                                                                get:NULL
                                                             detail:Nil
                                                               cell:PSStaticTextCell
                                                               edit:Nil];
        [openApp setProperty:@"customApp" forKey:@"actionID"];
        openApp->action = @selector(selectAction:);
        [specs addObject:openApp];

        PSSpecifier *shortcut = [PSSpecifier preferenceSpecifierNamed:@"Run Shortcut..."
                                                              target:self
                                                                 set:NULL
                                                                 get:NULL
                                                              detail:Nil
                                                                cell:PSStaticTextCell
                                                                edit:Nil];
        [shortcut setProperty:@"customShortcut" forKey:@"actionID"];
        shortcut->action = @selector(selectAction:);
        [specs addObject:shortcut];

        _specifiers = specs;
    }
    return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];

    // Show checkmark on currently selected action
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    NSString *actionID = [spec propertyForKey:@"actionID"];
    if (actionID && ![actionID hasPrefix:@"custom"]) {
        cell.accessoryType = [_currentValue isEqualToString:actionID] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else if ([actionID isEqualToString:@"customApp"] && [_currentValue hasPrefix:@"app:"]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else if ([actionID isEqualToString:@"customShortcut"] && [_currentValue hasPrefix:@"shortcut:"]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

- (void)selectAction:(PSSpecifier *)specifier {
    NSString *actionID = [specifier propertyForKey:@"actionID"];

    if ([actionID isEqualToString:@"customApp"]) {
        [self promptForCustomValue:@"Open App" message:@"Enter the app bundle ID (e.g. com.apple.Music):" prefix:@"app:"];
    } else if ([actionID isEqualToString:@"customShortcut"]) {
        [self promptForCustomValue:@"Run Shortcut" message:@"Enter the Siri Shortcut name:" prefix:@"shortcut:"];
    } else {
        [self saveAction:actionID];
    }
}

- (void)promptForCustomValue:(NSString *)title message:(NSString *)message prefix:(NSString *)prefix {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;

        // Pre-fill if current value matches this prefix
        if ([self->_currentValue hasPrefix:prefix]) {
            textField.text = [self->_currentValue substringFromIndex:prefix.length];
        }
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *value = alert.textFields.firstObject.text;
        if (value.length > 0) {
            [self saveAction:[NSString stringWithFormat:@"%@%@", prefix, value]];
        }
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveAction:(NSString *)actionID {
    _currentValue = actionID;

    CFPreferencesSetAppValue((__bridge CFStringRef)_prefKey,
                             (__bridge CFPropertyListRef)actionID,
                             (__bridge CFStringRef)PREFS_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);

    // Notify the tweak
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)PREFS_NOTIFICATION,
                                         NULL, NULL, YES);

    // Refresh checkmarks
    [self.table reloadData];
}

@end
