//
//  AppDelegate.m
//
// SensibleSideButtons, a utility that fixes the navigation buttons on third-party mice in macOS
// Copyright (C) 2018 Alexei Baboulevitch (ssb@archagon.net)
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.

#import "AppDelegate.h"
#import "TouchEvents.h"
#import <ServiceManagement/ServiceManagement.h>

static NSString * const SBFWebsiteURLString = @"https://sensible-side-buttons.archagon.net";
static NSString * const SBFSupportURLString = @"https://sensible-side-buttons.archagon.net#donations";

static NSMutableDictionary<NSNumber *, NSArray<NSDictionary *> *> *swipeInfo = nil;
static NSArray *nullArray = nil;

typedef NS_ENUM(NSInteger, MenuMode) {
    MenuModeAccessibility,
    MenuModeNormal
};

@interface AppDelegate ()
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, assign) CFMachPortRef tap;
@property (nonatomic, assign) MenuMode menuMode;
@property (nonatomic, copy) NSString *frontmostBundleID;
@property (nonatomic, strong) NSMenuItem *ignoreAppItem;
@end

static BOOL SBFRequestListenEventAccess(void) {
    if (@available(macOS 10.15, *)) {
        if (CGPreflightListenEventAccess()) {
            return YES;
        }
        CGRequestListenEventAccess();
        return CGPreflightListenEventAccess();
    }
    return YES;
}

static BOOL SBFShouldHandleEventForFrontmostApp(void) {
    NSRunningApplication *front = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *bundleID = front.bundleIdentifier;
    if (bundleID.length == 0) {
        return YES;
    }
    NSArray<NSString *> *ignored = [[NSUserDefaults standardUserDefaults] stringArrayForKey:@"SBFIgnoredApplications"];
    return ![ignored containsObject:bundleID];
}

static void SBFFakeSwipe(TLInfoSwipeDirection dir) {
    CGEventRef event1 = tl_CGEventCreateFromGesture((__bridge CFDictionaryRef)(swipeInfo[@(dir)][0]), (__bridge CFArrayRef)nullArray);
    CGEventRef event2 = tl_CGEventCreateFromGesture((__bridge CFDictionaryRef)(swipeInfo[@(dir)][1]), (__bridge CFArrayRef)nullArray);

    CGEventPost(kCGHIDEventTap, event1);
    CGEventPost(kCGHIDEventTap, event2);

    CFRelease(event1);
    CFRelease(event2);
}

static CGEventRef SBFMouseCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    AppDelegate *delegate = (__bridge AppDelegate *)refcon;

    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (delegate.tap != NULL) {
            CGEventTapEnable(delegate.tap, true);
        }
        return NULL;
    }

    if (!SBFShouldHandleEventForFrontmostApp()) {
        return event;
    }

    int64_t number = CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
    BOOL down = (type == kCGEventOtherMouseDown);

    BOOL mouseDown = [[NSUserDefaults standardUserDefaults] boolForKey:@"SBFMouseDown"];
    BOOL swapButtons = [[NSUserDefaults standardUserDefaults] boolForKey:@"SBFSwapButtons"];

    if (number == (swapButtons ? 4 : 3)) {
        if ((mouseDown && down) || (!mouseDown && !down)) {
            SBFFakeSwipe(kTLInfoSwipeLeft);
        }
        return NULL;
    }
    if (number == (swapButtons ? 3 : 4)) {
        if ((mouseDown && down) || (!mouseDown && !down)) {
            SBFFakeSwipe(kTLInfoSwipeRight);
        }
        return NULL;
    }
    return event;
}

@interface AboutView : NSView
@property (nonatomic, strong) NSTextView *text;
@property (nonatomic, assign) MenuMode menuMode;
- (CGFloat)margin;
@end

typedef NS_ENUM(NSInteger, MenuItem) {
    MenuItemEnabled = 0,
    MenuItemEnabledSeparator,
    MenuItemTriggerOnMouseDown,
    MenuItemSwapButtons,
    MenuItemIgnoreApp,
    MenuItemOptionsSeparator,
    MenuItemStartupHide,
    MenuItemStartupHideInfo,
    MenuItemLaunchAtLogin,
    MenuItemStartupSeparator,
    MenuItemAboutText,
    MenuItemAboutSeparator,
    MenuItemSupport,
    MenuItemWebsite,
    MenuItemAccessibility,
    MenuItemLinkSeparator,
    MenuItemQuit
};

@interface AppDelegate (MenuDelegate) <NSMenuDelegate>
@end

@implementation AppDelegate

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self startTap:NO];
    swipeInfo = nil;
    nullArray = nil;
}

- (void)setMenuMode:(MenuMode)menuMode {
    _menuMode = menuMode;
    AboutView *view = (AboutView *)self.statusItem.menu.itemArray[MenuItemAboutText].view;
    view.menuMode = menuMode;
    [self refreshSettings];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (@available(macOS 10.12, *)) {
        self.statusItem.visible = YES;
    }
    return NO;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        @"SBFWasEnabled": @YES,
        @"SBFMouseDown": @YES,
        @"SBFSwapButtons": @NO,
        @"SBFIgnoredApplications": @[],
    }];

    swipeInfo = [NSMutableDictionary dictionary];
    for (NSNumber *direction in @[@(kTLInfoSwipeUp), @(kTLInfoSwipeDown), @(kTLInfoSwipeLeft), @(kTLInfoSwipeRight)]) {
        NSDictionary *swipeInfo1 = @{
            (__bridge id)kTLInfoKeyGestureSubtype: @(kTLInfoSubtypeSwipe),
            (__bridge id)kTLInfoKeyGesturePhase: @(1),
        };
        NSDictionary *swipeInfo2 = @{
            (__bridge id)kTLInfoKeyGestureSubtype: @(kTLInfoSubtypeSwipe),
            (__bridge id)kTLInfoKeySwipeDirection: direction,
            (__bridge id)kTLInfoKeyGesturePhase: @(4),
        };
        swipeInfo[direction] = @[ swipeInfo1, swipeInfo2 ];
    }
    nullArray = @[];

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];

    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    menu.delegate = self;

    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Enabled" action:@selector(enabledToggle:) keyEquivalent:@"e"]];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:({
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Trigger on Mouse Down" action:@selector(mouseDownToggle:) keyEquivalent:@""];
        item.state = NSControlStateValueOn;
        item;
    })];
    [menu addItem:({
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Swap Buttons" action:@selector(swapToggle:) keyEquivalent:@""];
        item.state = NSControlStateValueOff;
        item;
    })];
    self.ignoreAppItem = [[NSMenuItem alloc] initWithTitle:@"Ignore Frontmost App" action:@selector(ignoreAppToggle:) keyEquivalent:@""];
    self.ignoreAppItem.hidden = YES;
    [menu addItem:self.ignoreAppItem];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Hide Menu Bar Icon" action:@selector(hideMenubarItem:) keyEquivalent:@""]];
    [menu addItem:({
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Relaunch application to show again" action:NULL keyEquivalent:@""];
        item.enabled = NO;
        item;
    })];
    NSMenuItem *launchItem = [[NSMenuItem alloc] initWithTitle:@"Launch at Login" action:@selector(launchAtLoginToggle:) keyEquivalent:@""];
    if (@available(macOS 13.0, *)) {
        launchItem.hidden = NO;
    } else {
        launchItem.hidden = YES;
    }
    [menu addItem:launchItem];
    [menu addItem:[NSMenuItem separatorItem]];

    AboutView *aboutView = [[AboutView alloc] initWithFrame:NSMakeRect(0, 0, 320, 100)];
    NSMenuItem *aboutText = [[NSMenuItem alloc] initWithTitle:@"About" action:NULL keyEquivalent:@""];
    aboutText.view = aboutView;
    [menu addItem:aboutText];
    [menu addItem:[NSMenuItem separatorItem]];

    NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"] ?: @"SensibleSideButtons";
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Support the Project" action:@selector(support:) keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ Website", appName] action:@selector(website:) keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Open Accessibility Settings" action:@selector(accessibility:) keyEquivalent:@""]];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@"q"];
    quit.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [menu addItem:quit];

    self.statusItem.menu = menu;

    NSNotificationCenter *center = [NSWorkspace sharedWorkspace].notificationCenter;
    [center addObserver:self selector:@selector(sessionDidBecomeActive:) name:NSWorkspaceSessionDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(sessionDidResignActive:) name:NSWorkspaceSessionDidResignActiveNotification object:nil];

    SBFRequestListenEventAccess();
    [self startTap:[[NSUserDefaults standardUserDefaults] boolForKey:@"SBFWasEnabled"]];
    [self updateMenuMode];
    [self refreshSettings];
}

- (void)sessionDidBecomeActive:(NSNotification *)notification {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"SBFWasEnabled"]) {
        [self recreateEventTap];
    }
}

- (void)sessionDidResignActive:(NSNotification *)notification {
    if (self.tap != NULL) {
        CGEventTapEnable(self.tap, NO);
    }
}

- (void)recreateEventTap {
    BOOL shouldRun = self.tap != NULL && CGEventTapIsEnabled(self.tap);
    if (!shouldRun) {
        shouldRun = [[NSUserDefaults standardUserDefaults] boolForKey:@"SBFWasEnabled"];
    }
    [self startTap:NO];
    [self startTap:shouldRun];
    [self refreshSettings];
}

- (void)updateMenuMode {
    [self updateMenuMode:YES];
}

- (void)updateMenuMode:(BOOL)promptForAccessibility {
    NSDictionary *options = @{ (__bridge id)kAXTrustedCheckOptionPrompt: @(promptForAccessibility) };
    BOOL accessibilityEnabled = AXIsProcessTrustedWithOptions((CFDictionaryRef)options);
    BOOL listenAccess = SBFRequestListenEventAccess();

    self.menuMode = (accessibilityEnabled && listenAccess) ? MenuModeNormal : MenuModeAccessibility;
}

- (BOOL)isEventTapActive {
    return self.tap != NULL && CGEventTapIsEnabled(self.tap);
}

- (void)refreshSettings {
    self.statusItem.menu.itemArray[MenuItemEnabled].state = [self isEventTapActive] ? NSControlStateValueOn : NSControlStateValueOff;
    self.statusItem.menu.itemArray[MenuItemTriggerOnMouseDown].state =
        [[NSUserDefaults standardUserDefaults] boolForKey:@"SBFMouseDown"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.statusItem.menu.itemArray[MenuItemSwapButtons].state =
        [[NSUserDefaults standardUserDefaults] boolForKey:@"SBFSwapButtons"] ? NSControlStateValueOn : NSControlStateValueOff;

    BOOL permissionsOK = (self.menuMode == MenuModeNormal);
    self.statusItem.menu.itemArray[MenuItemEnabled].enabled = permissionsOK;
    self.statusItem.menu.itemArray[MenuItemTriggerOnMouseDown].enabled = permissionsOK;
    self.statusItem.menu.itemArray[MenuItemSwapButtons].enabled = permissionsOK;
    self.ignoreAppItem.enabled = permissionsOK && self.frontmostBundleID.length > 0;

    self.statusItem.menu.itemArray[MenuItemAccessibility].hidden = permissionsOK;

    NSMenuItem *launchItem = self.statusItem.menu.itemArray[MenuItemLaunchAtLogin];
    if (@available(macOS 13.0, *)) {
        launchItem.state = ([SMAppService mainAppService].status == SMAppServiceStatusEnabled) ? NSControlStateValueOn : NSControlStateValueOff;
        launchItem.enabled = YES;
    } else {
        launchItem.state = NSControlStateValueOff;
        launchItem.enabled = NO;
    }

    if (@available(macOS 10.12, *)) {
        self.statusItem.menu.itemArray[MenuItemStartupHide].hidden = NO;
        self.statusItem.menu.itemArray[MenuItemStartupHideInfo].hidden = NO;
    } else {
        self.statusItem.menu.itemArray[MenuItemStartupHide].hidden = YES;
        self.statusItem.menu.itemArray[MenuItemStartupHideInfo].hidden = YES;
    }

    AboutView *view = (AboutView *)self.statusItem.menu.itemArray[MenuItemAboutText].view;
    [view layoutSubtreeIfNeeded];
    view.frame = NSMakeRect(0, 0, view.bounds.size.width, view.text.frame.size.height);

    if (self.statusItem.button != nil) {
        self.statusItem.button.image = [NSImage imageNamed:[self isEventTapActive] ? @"MenuIcon" : @"MenuIconDisabled"];
    }
}

- (void)showTapFailureAlert {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Could Not Enable Mouse Buttons";
        alert.informativeText = @"SensibleSideButtons needs Input Monitoring and Accessibility permission. Open System Settings → Privacy & Security, enable both for this app, then toggle Enabled again.";
        [alert addButtonWithTitle:@"Open Accessibility Settings"];
        [alert addButtonWithTitle:@"OK"];
        if (@available(macOS 10.15, *)) {
            CGRequestListenEventAccess();
        }
        NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            [self accessibility:nil];
        }
    });
}

- (void)startTap:(BOOL)start {
    if (start) {
        if (self.tap == NULL) {
            self.tap = CGEventTapCreate(kCGHIDEventTap,
                                        kCGHeadInsertEventTap,
                                        kCGEventTapOptionDefault,
                                        CGEventMaskBit(kCGEventOtherMouseUp) | CGEventMaskBit(kCGEventOtherMouseDown),
                                        &SBFMouseCallback,
                                        (__bridge void *)self);

            if (self.tap != NULL) {
                CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(NULL, self.tap, 0);
                CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
                CFRelease(runLoopSource);
                CGEventTapEnable(self.tap, true);
            } else {
                [self showTapFailureAlert];
            }
        } else {
            CGEventTapEnable(self.tap, true);
        }
    } else if (self.tap != NULL) {
        CGEventTapEnable(self.tap, NO);
        CFRelease(self.tap);
        self.tap = NULL;
    }

    [[NSUserDefaults standardUserDefaults] setBool:[self isEventTapActive] forKey:@"SBFWasEnabled"];
}

- (void)enabledToggle:(id)sender {
    if (self.tap == NULL) {
        SBFRequestListenEventAccess();
        [self updateMenuMode:YES];
    }
    [self startTap:![self isEventTapActive]];
    [self refreshSettings];
}

- (void)mouseDownToggle:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:![defaults boolForKey:@"SBFMouseDown"] forKey:@"SBFMouseDown"];
    [self refreshSettings];
}

- (void)swapToggle:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:![defaults boolForKey:@"SBFSwapButtons"] forKey:@"SBFSwapButtons"];
    [self refreshSettings];
}

- (void)ignoreAppToggle:(id)sender {
    NSString *bundleID = self.frontmostBundleID;
    if (bundleID.length == 0) {
        return;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray<NSString *> *ignored = [[defaults stringArrayForKey:@"SBFIgnoredApplications"] mutableCopy] ?: [NSMutableArray array];
    if ([ignored containsObject:bundleID]) {
        [ignored removeObject:bundleID];
    } else {
        [ignored addObject:bundleID];
    }
    [defaults setObject:ignored forKey:@"SBFIgnoredApplications"];
    [self refreshIgnoreMenuItem];
}

- (void)refreshIgnoreMenuItem {
    NSString *bundleID = self.frontmostBundleID;
    if (bundleID.length == 0) {
        self.ignoreAppItem.hidden = YES;
        return;
    }
    self.ignoreAppItem.hidden = NO;
    NSRunningApplication *front = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *name = front.localizedName ?: bundleID;
    NSArray<NSString *> *ignored = [[NSUserDefaults standardUserDefaults] stringArrayForKey:@"SBFIgnoredApplications"];
    BOOL isIgnored = [ignored containsObject:bundleID];
    self.ignoreAppItem.title = isIgnored ? [NSString stringWithFormat:@"Unignore %@", name] : [NSString stringWithFormat:@"Ignore %@", name];
    self.ignoreAppItem.state = isIgnored ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)support:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:SBFSupportURLString]];
}

- (void)website:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:SBFWebsiteURLString]];
}

- (void)accessibility:(id)sender {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    [[NSWorkspace sharedWorkspace] openURL:url];
    if (@available(macOS 10.15, *)) {
        CGRequestListenEventAccess();
    }
    [self updateMenuMode:NO];
    [self refreshSettings];
}

- (void)launchAtLoginToggle:(id)sender {
    if (@available(macOS 13.0, *)) {
        SMAppService *service = [SMAppService mainAppService];
        NSError *error = nil;
        if (service.status == SMAppServiceStatusEnabled) {
            [service unregisterAndReturnError:&error];
        } else {
            [service registerAndReturnError:&error];
        }
        if (error != nil) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Launch at Login Failed";
            alert.informativeText = error.localizedDescription;
            [alert runModal];
        }
        [self refreshSettings];
    }
}

- (void)hideMenubarItem:(id)sender {
    if (@available(macOS 10.12, *)) {
        self.statusItem.visible = NO;
    }
}

- (void)quit:(id)sender {
    [NSApp terminate:self];
}

- (void)menuWillOpen:(NSMenu *)menu {
    NSRunningApplication *front = [[NSWorkspace sharedWorkspace] frontmostApplication];
    self.frontmostBundleID = front.bundleIdentifier;
    [self updateMenuMode:NO];
    [self refreshIgnoreMenuItem];

    if (![self isEventTapActive] && [[NSUserDefaults standardUserDefaults] boolForKey:@"SBFWasEnabled"]) {
        [self recreateEventTap];
    }
    [self refreshSettings];
}

@end

@implementation AboutView

- (CGFloat)margin {
    return 17;
}

- (void)setMenuMode:(MenuMode)menuMode {
    _menuMode = menuMode;

    NSFont *font = [NSFont menuFontOfSize:13];
    NSFontDescriptor *boldFontDesc = [[NSFontDescriptor alloc] initWithFontAttributes:@{
        NSFontFamilyAttribute: font.familyName,
        NSFontFaceAttribute: @"Bold",
    }];
    NSFont *boldFont = [NSFont fontWithDescriptor:boldFontDesc size:font.pointSize] ?: font;

    NSColor *regularColor = [NSColor secondaryLabelColor];
    NSColor *alertColor = [NSColor systemRedColor];

    NSDictionary *regularAttributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: regularColor,
    };
    NSDictionary *alertAttributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: alertColor,
    };
    NSDictionary *smallReturnAttributes = @{
        NSFontAttributeName: [NSFont menuFontOfSize:3],
    };

    NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"] ?: @"SensibleSideButtons";
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSString *appDescription = [NSString stringWithFormat:@"%@ %@", appName, version];
    NSString *copyright = @"Copyright © 2018 Alexei Baboulevitch. Maintained fork build.";

    NSMutableAttributedString *string;
    if (menuMode == MenuModeAccessibility) {
        NSString *text = [NSString stringWithFormat:@"%@ needs Input Monitoring and Accessibility permission in System Settings → Privacy & Security before it can remap mouse side buttons.", appDescription];
        string = [[NSMutableAttributedString alloc] initWithString:text attributes:alertAttributes];
        [string addAttribute:NSFontAttributeName value:boldFont range:[text rangeOfString:appDescription]];
    } else {
        NSString *text = [NSString stringWithFormat:@"Thanks for using %@! Side buttons simulate three-finger swipes for back and forward navigation.", appDescription];
        string = [[NSMutableAttributedString alloc] initWithString:text attributes:regularAttributes];
        [string addAttribute:NSFontAttributeName value:boldFont range:[text rangeOfString:appDescription]];
    }

    [string appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:regularAttributes]];
    [string appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:smallReturnAttributes]];
    [string appendAttributedString:[[NSAttributedString alloc] initWithString:copyright attributes:regularAttributes]];
    [self.text.textStorage setAttributedString:string];
    [self setNeedsLayout:YES];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.text = [NSTextView new];
        self.text.backgroundColor = NSColor.clearColor;
        self.text.editable = NO;
        self.text.selectable = NO;
        [self addSubview:self.text];
        self.menuMode = MenuModeNormal;
    }
    return self;
}

- (void)layout {
    [super layout];
    CGFloat margin = [self margin];
    CGFloat arbitraryHeight = 100;
    self.text.frame = NSMakeRect(margin, 0, self.bounds.size.width - margin, arbitraryHeight);
    [self.text sizeToFit];
    self.text.frame = NSMakeRect(self.text.frame.origin.x,
                                 self.bounds.size.height - self.text.frame.size.height,
                                 self.text.frame.size.width,
                                 self.text.frame.size.height);
}

@end
