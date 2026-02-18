#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ABMCClickType) {
    ABMCClickTypeSingle = 1,
    ABMCClickTypeDouble = 2,
};

typedef void (^ABMCClickCallback)(ABMCClickType clickType);

@interface ABMCClickManager : NSObject

@property (nonatomic, copy) ABMCClickCallback clickCallback;
@property (nonatomic, assign) NSTimeInterval clickTimeout;

+ (instancetype)sharedManager;
- (void)registerClick;
- (void)cancelPendingClicks;

@end
