#import "UpdateBanner.h"

#import "CoreBridge.h"

static const NSTimeInterval kRetrySeconds = 0.25;
static const CGFloat kPillHeight          = 36.0;
static const CGFloat kPillPadding         = 16.0;

static UIWindow *bannerWindow = nil;
static UIWindow *warningWindow = nil;
static uint64_t warningGeneration = 0;
static BOOL wanted            = NO;

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

+ (void)showIntegrityWarning
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *scene = hostScene();
        if (!scene)
        {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t) (kRetrySeconds * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self showIntegrityWarning]; });
            return;
        }

        UIWindow *previous = warningWindow;
        warningWindow = nil;
        previous.hidden = YES;

        UIVisualEffectView *pill = [[UIVisualEffectView alloc]
            initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
        pill.layer.cornerRadius = 18.0;
        pill.layer.masksToBounds = YES;

        UIImageView *icon = [[UIImageView alloc]
            initWithImage:[UIImage systemImageNamed:@"exclamationmark.triangle.fill"]];
        icon.tintColor = UIColor.systemOrangeColor;
        icon.contentMode = UIViewContentModeScaleAspectFit;

        UILabel *label = [[UILabel alloc] init];
        label.text = @"Unbound couldn't verify this build.";
        label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
        label.textColor = UIColor.labelColor;
        label.numberOfLines = 1;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ icon, label ]];
        stack.spacing = 9.0;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [pill.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [icon.widthAnchor constraintEqualToConstant:16.0],
            [icon.heightAnchor constraintEqualToConstant:16.0],
            [stack.centerYAnchor constraintEqualToAnchor:pill.contentView.centerYAnchor],
            [stack.leadingAnchor constraintEqualToAnchor:pill.contentView.leadingAnchor constant:16.0],
            [stack.trailingAnchor constraintEqualToAnchor:pill.contentView.trailingAnchor constant:-16.0],
            [pill.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
        ]];

        UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
        window.windowLevel = UIWindowLevelStatusBar + 1;
        window.userInteractionEnabled = NO;
        window.backgroundColor = UIColor.clearColor;
        window.rootViewController = [[UIViewController alloc] init];
        window.rootViewController.view.backgroundColor = UIColor.clearColor;
        pill.translatesAutoresizingMaskIntoConstraints = NO;
        [window.rootViewController.view addSubview:pill];
        [NSLayoutConstraint activateConstraints:@[
            [pill.centerXAnchor constraintEqualToAnchor:window.rootViewController.view.centerXAnchor],
            [pill.topAnchor constraintEqualToAnchor:window.rootViewController.view.safeAreaLayoutGuide.topAnchor constant:8.0],
        ]];

        window.alpha = 0.0;
        window.hidden = NO;
        warningWindow = window;
        uint64_t generation = ++warningGeneration;
        [UIView animateWithDuration:0.2 animations:^{ window.alpha = 1.0; }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (generation != warningGeneration || warningWindow != window)
            {
                return;
            }
            [UIView animateWithDuration:0.2 animations:^{ window.alpha = 0.0; }
                             completion:^(BOOL finished) {
                if (warningWindow == window)
                {
                    window.hidden = YES;
                    warningWindow = nil;
                }
            }];
        });
    });
}

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

@end
