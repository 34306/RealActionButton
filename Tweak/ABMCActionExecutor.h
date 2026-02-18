#import <Foundation/Foundation.h>

extern BOOL ABMCPerformingDefaultAction;

@interface ABMCActionExecutor : NSObject

@property (nonatomic, weak) id buttonInstance;
@property (nonatomic, strong) id lastDownEvent;

+ (instancetype)sharedExecutor;
- (void)executeActionForClickType:(NSInteger)clickType;
- (void)executeAction:(NSString *)actionID;
- (void)reloadPreferences;

@end
