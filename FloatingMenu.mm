#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

@interface FloatingMenuManager : NSObject

@property (nonatomic, strong) UIButton *bubbleButton;
@property (nonatomic, strong) UIView *menuView;
@property (nonatomic, strong) NSTimer *idleTimer;
@property (nonatomic, assign) BOOL isRetracted;
@property (nonatomic, assign) BOOL isMenuOpen;

+ (instancetype)sharedInstance;
- (void)setupUI;

@end

@implementation FloatingMenuManager

+ (instancetype)sharedInstance {
    static FloatingMenuManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[FloatingMenuManager alloc] init];
    });
    return instance;
}

- (UIWindow *)activeWindow {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *w in windowScene.windows) {
                    if (w.isKeyWindow) {
                        window = w;
                        break;
                    }
                }
                if (!window && windowScene.windows.count > 0) {
                    window = windowScene.windows.firstObject;
                }
            }
            if (window) break;
        }
    }
    if (!window) {
        window = [UIApplication sharedApplication].keyWindow;
    }
    if (!window && [UIApplication sharedApplication].windows.count > 0) {
        window = [UIApplication sharedApplication].windows.firstObject;
    }
    return window;
}

- (void)setupUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [self activeWindow];
        if (!window) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self setupUI];
            });
            return;
        }

        if (self.bubbleButton) {
            [window bringSubviewToFront:self.bubbleButton];
            return;
        }

        CGFloat bubbleSize = 52.0;
        CGSize screenSize = window.bounds.size;

        // 1. Khởi tạo bong bóng tròn
        self.bubbleButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.bubbleButton.frame = CGRectMake(12.0, screenSize.height * 0.35, bubbleSize, bubbleSize);
        self.bubbleButton.backgroundColor = [UIColor colorWithRed:0.12 green:0.14 blue:0.18 alpha:0.92];
        self.bubbleButton.layer.cornerRadius = bubbleSize / 2.0;
        self.bubbleButton.layer.borderWidth = 2.0;
        self.bubbleButton.layer.borderColor = [UIColor colorWithRed:0.35 green:0.65 blue:1.0 alpha:0.95].CGColor;
        self.bubbleButton.layer.shadowColor = [UIColor blackColor].CGColor;
        self.bubbleButton.layer.shadowOpacity = 0.45;
        self.bubbleButton.layer.shadowOffset = CGSizeMake(0, 3);
        self.bubbleButton.layer.shadowRadius = 6.0;
        self.bubbleButton.layer.zPosition = 9999;

        [self.bubbleButton setTitle:@"HN" forState:UIControlStateNormal];
        [self.bubbleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.bubbleButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];

        [self.bubbleButton addTarget:self action:@selector(handleBubbleTap) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self.bubbleButton addGestureRecognizer:panGesture];

        [window addSubview:self.bubbleButton];

        // 2. Khởi tạo khung Menu (mặc định ẩn)
        [self createMenuInWindow:window];

        // 3. Bắt đầu đếm ngược để tự lui vào mép
        [self resetIdleTimer];
    });
}

- (UIButton *)createMenuButtonWithTitle:(NSString *)title
                                yOffset:(CGFloat)yOffset
                              menuWidth:(CGFloat)menuWidth
                                bgColor:(UIColor *)bgColor
                               selector:(SEL)selector {
    CGFloat btnWidth = menuWidth - 40.0;
    CGFloat btnHeight = 42.0;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake((menuWidth - btnWidth) / 2.0, yOffset, btnWidth, btnHeight);
    btn.backgroundColor = bgColor;
    btn.layer.cornerRadius = 10.0;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    btn.titleLabel.textAlignment = NSTextAlignmentCenter;
    [btn addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)createMenuInWindow:(UIWindow *)window {
    CGFloat menuWidth = 270.0;
    CGFloat menuHeight = 232.0;
    CGSize screenSize = window.bounds.size;

    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(
        (screenSize.width - menuWidth) / 2.0,
        (screenSize.height - menuHeight) / 2.0,
        menuWidth,
        menuHeight
    )];
    self.menuView.backgroundColor = [UIColor clearColor];
    self.menuView.layer.cornerRadius = 16.0;
    self.menuView.clipsToBounds = YES;
    self.menuView.layer.borderWidth = 1.2;
    self.menuView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
    self.menuView.layer.zPosition = 9998;
    self.menuView.hidden = YES;
    self.menuView.alpha = 0.0;

    // Hiệu ứng làm mờ nền (Blur)
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.frame = self.menuView.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.menuView addSubview:blurView];

    // Thanh tiêu đề: "- Việt Hóa by Hoàng Nguyễn -"
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, menuWidth, 48.0)];
    headerView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    UIPanGestureRecognizer *menuPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleMenuPan:)];
    [headerView addGestureRecognizer:menuPan];
    [self.menuView addSubview:headerView];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, menuWidth - 16, 48.0)];
    titleLabel.text = @"- Việt Hóa by Hoàng Nguyễn -";
    titleLabel.textColor = [UIColor colorWithRed:1.0 green:0.84 blue:0.25 alpha:1.0];
    titleLabel.font = [UIFont boldSystemFontOfSize:14.5];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [headerView addSubview:titleLabel];

    // Nút 1: Facebook -> mở trình duyệt vào fb.com/mrhoang0410
    UIButton *fbButton = [self createMenuButtonWithTitle:@"Facebook"
                                                 yOffset:62.0
                                               menuWidth:menuWidth
                                                 bgColor:[UIColor colorWithRed:0.09 green:0.47 blue:0.95 alpha:0.92]
                                                selector:@selector(openFacebook)];
    [self.menuView addSubview:fbButton];

    // Nút 2: Zalo -> nhảy sang Zalo tìm số 085.287.8864
    UIButton *zaloButton = [self createMenuButtonWithTitle:@"Zalo"
                                                   yOffset:116.0
                                                 menuWidth:menuWidth
                                                   bgColor:[UIColor colorWithRed:0.0 green:0.41 blue:1.0 alpha:0.92]
                                                  selector:@selector(openZalo)];
    [self.menuView addSubview:zaloButton];

    // Nút 3: Số Điện Thoại -> gọi điện vào số 0852878864
    UIButton *phoneButton = [self createMenuButtonWithTitle:@"Số Điện Thoại"
                                                    yOffset:170.0
                                                  menuWidth:menuWidth
                                                    bgColor:[UIColor colorWithRed:0.16 green:0.65 blue:0.27 alpha:0.92]
                                                   selector:@selector(callPhoneNumber)];
    [self.menuView addSubview:phoneButton];

    [window addSubview:self.menuView];
}

#pragma mark - Các hành động trong Menu

- (void)openURLString:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 10.0, *)) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            [[UIApplication sharedApplication] openURL:url];
#pragma clang diagnostic pop
        }
    });
}

- (void)openFacebook {
    [self openURLString:@"https://fb.com/mrhoang0410"];
}

- (void)openZalo {
    [self openURLString:@"https://zalo.me/0852878864"];
}

- (void)callPhoneNumber {
    [self openURLString:@"tel://0852878864"];
}

#pragma mark - Xử lý Kéo thả & Tự động lui vào mép

- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    UIWindow *window = [self activeWindow];
    if (!window) return;

    CGPoint translation = [recognizer translationInView:window];

    if (recognizer.state == UIGestureRecognizerStateBegan) {
        [self stopIdleTimer];
        [self restoreBubbleFromEdgeAnimated:YES];
    } else if (recognizer.state == UIGestureRecognizerStateChanged) {
        CGPoint newCenter = CGPointMake(
            self.bubbleButton.center.x + translation.x,
            self.bubbleButton.center.y + translation.y
        );

        CGFloat halfSize = self.bubbleButton.bounds.size.width / 2.0;
        CGSize screenSize = window.bounds.size;
        newCenter.x = MAX(halfSize, MIN(screenSize.width - halfSize, newCenter.x));
        newCenter.y = MAX(halfSize + 20.0, MIN(screenSize.height - halfSize - 20.0, newCenter.y));

        self.bubbleButton.center = newCenter;
        [recognizer setTranslation:CGPointZero inView:window];
    } else if (recognizer.state == UIGestureRecognizerStateEnded ||
               recognizer.state == UIGestureRecognizerStateCancelled) {
        [self snapToNearestEdge];
        [self resetIdleTimer];
    }
}

- (void)handleMenuPan:(UIPanGestureRecognizer *)recognizer {
    UIWindow *window = [self activeWindow];
    if (!window) return;

    CGPoint translation = [recognizer translationInView:window];
    if (recognizer.state == UIGestureRecognizerStateChanged) {
        self.menuView.center = CGPointMake(
            self.menuView.center.x + translation.x,
            self.menuView.center.y + translation.y
        );
        [recognizer setTranslation:CGPointZero inView:window];
    }
}

- (void)snapToNearestEdge {
    UIWindow *window = [self activeWindow];
    if (!window) return;

    CGSize screenSize = window.bounds.size;
    CGFloat halfWidth = self.bubbleButton.bounds.size.width / 2.0;
    CGFloat margin = 8.0;

    BOOL isLeft = (self.bubbleButton.center.x < screenSize.width / 2.0);
    CGFloat targetX = isLeft ? (halfWidth + margin) : (screenSize.width - halfWidth - margin);

    [UIView animateWithDuration:0.28
                          delay:0
         usingSpringWithDamping:0.75
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.bubbleButton.center = CGPointMake(targetX, self.bubbleButton.center.y);
        self.bubbleButton.alpha = 1.0;
        self.isRetracted = NO;
    } completion:nil];
}

- (void)resetIdleTimer {
    [self stopIdleTimer];
    if (self.isMenuOpen) return;
    self.idleTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                      target:self
                                                    selector:@selector(retractBubbleToEdge)
                                                    userInfo:nil
                                                     repeats:NO];
}

- (void)stopIdleTimer {
    if (self.idleTimer) {
        [self.idleTimer invalidate];
        self.idleTimer = nil;
    }
}

- (void)retractBubbleToEdge {
    if (self.isMenuOpen || self.isRetracted) return;
    UIWindow *window = [self activeWindow];
    if (!window) return;

    CGSize screenSize = window.bounds.size;
    CGFloat halfWidth = self.bubbleButton.bounds.size.width / 2.0;
    BOOL isLeft = (self.bubbleButton.center.x < screenSize.width / 2.0);

    CGFloat hiddenOffset = halfWidth * 0.55;
    CGFloat targetX = isLeft ? (halfWidth - hiddenOffset) : (screenSize.width - halfWidth + hiddenOffset);

    [UIView animateWithDuration:0.35
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.bubbleButton.center = CGPointMake(targetX, self.bubbleButton.center.y);
        self.bubbleButton.alpha = 0.45;
        self.isRetracted = YES;
    } completion:nil];
}

- (void)restoreBubbleFromEdgeAnimated:(BOOL)animated {
    if (!self.isRetracted) return;
    [self snapToNearestEdge];
}

#pragma mark - Đóng / Mở Menu

- (void)handleBubbleTap {
    [self stopIdleTimer];

    if (self.isRetracted) {
        [self snapToNearestEdge];
    }

    if (self.isMenuOpen) {
        [self closeMenu];
    } else {
        [self openMenu];
    }
}

- (void)openMenu {
    UIWindow *window = [self activeWindow];
    if (window) {
        [window bringSubviewToFront:self.menuView];
        [window bringSubviewToFront:self.bubbleButton];
    }

    self.isMenuOpen = YES;
    self.menuView.hidden = NO;
    self.menuView.transform = CGAffineTransformMakeScale(0.85, 0.85);

    [UIView animateWithDuration:0.25
                          delay:0
         usingSpringWithDamping:0.8
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.menuView.alpha = 1.0;
        self.menuView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)closeMenu {
    self.isMenuOpen = NO;
    [UIView animateWithDuration:0.2
                     animations:^{
        self.menuView.alpha = 0.0;
        self.menuView.transform = CGAffineTransformMakeScale(0.85, 0.85);
    } completion:^(BOOL finished) {
        self.menuView.hidden = YES;
        self.menuView.transform = CGAffineTransformIdentity;
        [self resetIdleTimer];
    }];
}

@end

__attribute__((constructor))
static void initializeFloatingMenu() {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[FloatingMenuManager sharedInstance] setupUI];
        });
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[FloatingMenuManager sharedInstance] setupUI];
    });
}
