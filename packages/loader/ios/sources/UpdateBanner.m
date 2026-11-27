#import "UpdateBanner.h"

#import "CoreBridge.h"

static const NSTimeInterval kRetrySeconds = 0.25;
static const CGFloat kPillHeight          = 36.0;
static const CGFloat kPillPadding         = 16.0;

static UIWindow *bannerWindow  = nil;
static BOOL wanted             = NO;
static UIWindow *warningWindow = nil;
static BOOL warningWanted      = NO;

// Launch may still be on its storyboard; any connected window scene can host the pill.
static UIWindowScene *hostScene(void)
{
    UIWindowScene *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
    {
        if (![scene isKindOfClass:UIWindowScene.class])
        {
            continue;
        }

        if (scene.activationState == UISceneActivationStateForegroundActive)
        {
            return (UIWindowScene *) scene;
        }

        fallback = fallback ?: (UIWindowScene *) scene;
    }

    return fallback;
}

static UIView *pillView(void)
{
    UIVisualEffectView *pill = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    pill.layer.cornerRadius  = kPillHeight / 2.0;
    pill.layer.masksToBounds = YES;

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];

    UILabel *label = [[UILabel alloc] init];
    label.text     = [CoreBridge text:@"UNBOUND_NATIVE_UPDATING" english:@"Updating Unbound…"];
    label.font     = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ spinner, label ]];
    stack.spacing      = 8.0;
    stack.alignment    = UIStackViewAlignmentCenter;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [pill.contentView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerYAnchor constraintEqualToAnchor:pill.contentView.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:pill.contentView.leadingAnchor
                                            constant:kPillPadding],
        [stack.trailingAnchor constraintEqualToAnchor:pill.contentView.trailingAnchor
                                             constant:-kPillPadding],
        [pill.heightAnchor constraintEqualToConstant:kPillHeight],
    ]];
    return pill;
}

@implementation UpdateBanner

+ (void)show
{
    dispatch_async(dispatch_get_main_queue(), ^{
        wanted = YES;
        [self attach];
    });
}

+ (void)hide
{
    dispatch_async(dispatch_get_main_queue(), ^{
        wanted           = NO;
        UIWindow *window = bannerWindow;
        bannerWindow     = nil;
        [UIView animateWithDuration:0.25
            animations:^{ window.alpha = 0.0; }
            completion:^(BOOL finished) { window.hidden = YES; }];
    });
}

+ (void)attach
{
    if (!wanted || bannerWindow)
    {
        return;
    }

    UIWindowScene *scene = hostScene();
    if (!scene)
    {
        // No scene yet this early in launch: look again shortly while still wanted.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (kRetrySeconds * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self attach]; });
        return;
    }

    UIWindow *window                               = [[UIWindow alloc] initWithWindowScene:scene];
    window.windowLevel                             = UIWindowLevelStatusBar + 1;
    window.userInteractionEnabled                  = NO;
    window.backgroundColor                         = UIColor.clearColor;
    window.rootViewController                      = [[UIViewController alloc] init];
    window.rootViewController.view.backgroundColor = UIColor.clearColor;

    UIView *pill                                   = pillView();
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *root                                   = window.rootViewController.view;
    [root addSubview:pill];
    [NSLayoutConstraint activateConstraints:@[
        [pill.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [pill.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor constant:8.0],
    ]];

    window.alpha  = 0.0;
    window.hidden = NO;
    bannerWindow  = window;
    [UIView animateWithDuration:0.25 animations:^{ window.alpha = 1.0; }];
}


+ (void)showAttestationWarning
{
    dispatch_async(dispatch_get_main_queue(), ^{
        warningWanted = YES;
        [self attachAttestationWarning];
    });
}

+ (void)hideAttestationWarning
{
    dispatch_async(dispatch_get_main_queue(), ^{
        warningWanted    = NO;
        UIWindow *window = warningWindow;
        warningWindow    = nil;
        [UIView animateWithDuration:0.2
            animations:^{ window.alpha = 0.0; }
            completion:^(BOOL finished) { window.hidden = YES; }];
    });
}

+ (void)attachAttestationWarning
{
    if (!warningWanted || warningWindow)
    {
        return;
    }

    UIWindowScene *scene = hostScene();
    if (!scene)
    {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (kRetrySeconds * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self attachAttestationWarning]; });
        return;
    }

    UIWindow *window                               = [[UIWindow alloc] initWithWindowScene:scene];
    window.windowLevel                             = UIWindowLevelAlert - 1;
    window.userInteractionEnabled                  = YES;
    window.backgroundColor                         = UIColor.clearColor;
    window.rootViewController                      = [[UIViewController alloc] init];
    window.rootViewController.view.backgroundColor = UIColor.clearColor;

    UIVisualEffectView *card = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    card.layer.cornerRadius  = 14.0;
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *icon = [[UILabel alloc] init];
    icon.text = @"!";
    icon.textColor = UIColor.systemRedColor;
    icon.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightBold];
    icon.textAlignment = NSTextAlignmentCenter;

    UILabel *label = [[UILabel alloc] init];
    label.text = [CoreBridge text:@"UNBOUND_NATIVE_ATTESTATION_BANNER"
                           english:@"Unbound couldn't verify this build. Details are in the logs."];
    label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    label.textColor = UIColor.labelColor;
    label.numberOfLines = 2;
    label.lineBreakMode = NSLineBreakByWordWrapping;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"×" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightRegular];
    close.accessibilityLabel = @"Dismiss integrity warning";
    [close addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        [self hideAttestationWarning];
    }] forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ icon, label, close ]];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 10.0;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    [window.rootViewController.view addSubview:card];
    [card.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:window.rootViewController.view.safeAreaLayoutGuide.topAnchor
                                        constant:8.0],
        [card.leadingAnchor constraintEqualToAnchor:window.rootViewController.view.leadingAnchor
                                           constant:16.0],
        [card.trailingAnchor constraintEqualToAnchor:window.rootViewController.view.trailingAnchor
                                            constant:-16.0],
        [card.heightAnchor constraintEqualToConstant:68.0],
        [stack.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:12.0],
        [stack.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor constant:-8.0],
        [stack.centerYAnchor constraintEqualToAnchor:card.contentView.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:22.0],
        [close.widthAnchor constraintEqualToConstant:28.0],
    ]];

    window.alpha  = 0.0;
    window.hidden = NO;
    warningWindow = window;
    [UIView animateWithDuration:0.2 animations:^{ window.alpha = 1.0; }];
}

@end
