#import "ABMCClickManager.h"

@implementation ABMCClickManager {
    NSInteger _clickCount;
    dispatch_source_t _timer;
    dispatch_queue_t _queue;
}

+ (instancetype)sharedManager {
    static ABMCClickManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ABMCClickManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _clickCount = 0;
        _clickTimeout = 1.5;
        _queue = dispatch_queue_create("com.huynguyen.abmc.clickqueue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)registerClick {
    dispatch_async(_queue, ^{
        [self _cancelTimer];
        self->_clickCount++;

        if (self->_clickCount >= 2) {
            // Double click detected — fire immediately
            self->_clickCount = 0;
            [self _fireCallbackForCount:2];
            return;
        }

        // Start timer — if it expires, it's a single click
        [self _startTimer];
    });
}

- (void)cancelPendingClicks {
    dispatch_async(_queue, ^{
        [self _cancelTimer];
        self->_clickCount = 0;
    });
}

- (void)_startTimer {
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    uint64_t timeout = (uint64_t)(self.clickTimeout * NSEC_PER_SEC);
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, timeout), DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(_timer, ^{
        NSInteger count = self->_clickCount;
        self->_clickCount = 0;
        [self _cancelTimer];
        [self _fireCallbackForCount:count];
    });
    dispatch_resume(_timer);
}

- (void)_cancelTimer {
    if (_timer) {
        dispatch_source_cancel(_timer);
        _timer = nil;
    }
}

- (void)_fireCallbackForCount:(NSInteger)count {
    if (count < 1 || count > 2) return;
    ABMCClickType type = (ABMCClickType)count;
    if (self.clickCallback) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.clickCallback(type);
        });
    }
}

@end
