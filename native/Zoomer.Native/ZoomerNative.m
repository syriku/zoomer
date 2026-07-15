#import "ZoomerNative.h"
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

enum {
    ZMRErrorPermissionDenied = 1,
    ZMRErrorTargetDisplayUnavailable = 2,
    ZMRErrorCaptureFailed = 3,
    ZMRErrorCaptureCancelled = 4,
    ZMRErrorPresentationFailed = 5,
    ZMRErrorNativeBridgeFailed = 6,
};

static void *g_context;
static zmr_app_callbacks g_callbacks;
static EventHotKeyRef g_hotkey;
static EventHandlerRef g_hotkey_handler;

@interface ZMRAppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenuItem *presentItem;
@property(nonatomic, strong) NSMenuItem *permissionItem;
@property(nonatomic, strong) NSMenuItem *statusItemText;
@end

@implementation ZMRAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    NSImage *image = [NSImage imageWithSystemSymbolName:@"magnifyingglass.circle" accessibilityDescription:@"Zoomer"];
    image.template = YES;
    self.statusItem.button.image = image;
    self.statusItem.button.title = image ? @"" : @"Z";

    NSMenu *menu = [[NSMenu alloc] init];
    self.presentItem = [[NSMenuItem alloc] initWithTitle:@"进入工作模式" action:@selector(present:) keyEquivalent:@""];
    self.presentItem.target = self;
    [menu addItem:self.presentItem];
    self.permissionItem = [[NSMenuItem alloc] initWithTitle:@"屏幕录制权限…" action:@selector(permission:) keyEquivalent:@""];
    self.permissionItem.target = self;
    [menu addItem:self.permissionItem];
    self.statusItemText = [[NSMenuItem alloc] initWithTitle:@"空闲" action:nil keyEquivalent:@""];
    self.statusItemText.enabled = NO;
    [menu addItem:self.statusItemText];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出 Zoomer" action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];
    self.statusItem.menu = menu;
    self.permissionItem.title = CGPreflightScreenCaptureAccess() ? @"屏幕录制权限：已授权" : @"屏幕录制权限…";
    zmr_hotkey_register();
}
- (void)applicationWillTerminate:(NSNotification *)notification { zmr_hotkey_unregister(); }
- (void)present:(id)sender { if (g_callbacks.present_requested) g_callbacks.present_requested(g_context); }
- (void)permission:(id)sender { if (g_callbacks.permission_requested) g_callbacks.permission_requested(g_context); }
- (void)quit:(id)sender { if (g_callbacks.quit_requested) g_callbacks.quit_requested(g_context); }
@end

static ZMRAppDelegate *g_app_delegate;

static OSStatus ZMRHandleHotKey(EventHandlerCallRef next, EventRef event, void *context) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_callbacks.hotkey_triggered) g_callbacks.hotkey_triggered(g_context);
    });
    return noErr;
}

int32_t zmr_app_initialize(void *context, zmr_app_callbacks callbacks) {
    @autoreleasepool {
        g_context = context;
        g_callbacks = callbacks;
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        g_app_delegate = [[ZMRAppDelegate alloc] init];
        app.delegate = g_app_delegate;
        return 0;
    }
}

int32_t zmr_app_run(void) {
    @autoreleasepool { [NSApplication.sharedApplication run]; }
    return 0;
}

void zmr_app_stop(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [NSApplication.sharedApplication terminate:nil]; });
}

void zmr_app_set_menu(bool can_present, const char *status_text, bool authorized) {
    NSString *status = status_text ? [NSString stringWithUTF8String:status_text] : @"空闲";
    status = [status copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        g_app_delegate.presentItem.enabled = can_present;
        g_app_delegate.statusItemText.title = status;
        g_app_delegate.permissionItem.title = authorized ? @"屏幕录制权限：已授权" : @"屏幕录制权限…";
    });
}

bool zmr_hotkey_register(void) {
    if (g_hotkey) return true;
    EventTypeSpec type = { kEventClassKeyboard, kEventHotKeyPressed };
    if (InstallApplicationEventHandler(&ZMRHandleHotKey, 1, &type, NULL, &g_hotkey_handler) != noErr) return false;
    EventHotKeyID identifier = { 'ZMRK', 1 };
    if (RegisterEventHotKey(kVK_ANSI_Z, optionKey | cmdKey, identifier,
                            GetApplicationEventTarget(), 0, &g_hotkey) != noErr) {
        RemoveEventHandler(g_hotkey_handler);
        g_hotkey_handler = NULL;
        return false;
    }
    return true;
}

void zmr_hotkey_unregister(void) {
    if (g_hotkey) { UnregisterEventHotKey(g_hotkey); g_hotkey = NULL; }
    if (g_hotkey_handler) { RemoveEventHandler(g_hotkey_handler); g_hotkey_handler = NULL; }
}

bool zmr_permission_is_authorized(void) { return CGPreflightScreenCaptureAccess(); }
bool zmr_permission_request(void) { return CGRequestScreenCaptureAccess(); }
void zmr_permission_open_settings(void) {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"];
    [NSWorkspace.sharedWorkspace openURL:url];
}

static zmr_display_descriptor ZMRDescriptor(NSScreen *screen, CGDirectDisplayID displayID) {
    NSRect frame = screen.frame;
    return (zmr_display_descriptor){ displayID, frame.origin.x, frame.origin.y,
        frame.size.width, frame.size.height, screen.backingScaleFactor };
}

static void ZMRCaptureComplete(void *context, zmr_capture_callback callback,
                               int64_t requestID, CGImageRef image,
                               zmr_display_descriptor display, int32_t code,
                               NSString *message) {
    const char *utf8 = message ? message.UTF8String : NULL;
    callback(context, requestID, (void *)image, display, code, utf8);
}

void zmr_capture_display(int64_t requestID, void *context, zmr_capture_callback callback) {
    if (!callback) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!CGPreflightScreenCaptureAccess()) {
            ZMRCaptureComplete(context, callback, requestID, NULL, (zmr_display_descriptor){0},
                               ZMRErrorPermissionDenied, @"需要屏幕录制权限");
            return;
        }
        NSPoint location = NSEvent.mouseLocation;
        NSScreen *target = nil;
        for (NSScreen *screen in NSScreen.screens) {
            if (NSPointInRect(location, screen.frame)) { target = screen; break; }
        }
        if (!target) {
            ZMRCaptureComplete(context, callback, requestID, NULL, (zmr_display_descriptor){0},
                               ZMRErrorTargetDisplayUnavailable, @"目标显示器不可用");
            return;
        }
        NSScreen *screen = target;
        CGDirectDisplayID displayID = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        zmr_display_descriptor descriptor = ZMRDescriptor(screen, displayID);
        [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:NO
            completionHandler:^(SCShareableContent *content, NSError *error) {
            SCDisplay *display = nil;
            for (SCDisplay *candidate in content.displays) {
                if (candidate.displayID == displayID) { display = candidate; break; }
            }
            if (error || !display) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    ZMRCaptureComplete(context, callback, requestID, NULL, descriptor,
                                       ZMRErrorTargetDisplayUnavailable, @"目标显示器不可用");
                });
                return;
            }
            SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display excludingWindows:@[]];
            SCStreamConfiguration *configuration = [[SCStreamConfiguration alloc] init];
            configuration.width = (size_t)llround(descriptor.width * descriptor.backing_scale);
            configuration.height = (size_t)llround(descriptor.height * descriptor.backing_scale);
            configuration.showsCursor = NO;
            configuration.backgroundColor = NSColor.blackColor.CGColor;
            [SCScreenshotManager captureImageWithFilter:filter configuration:configuration
                completionHandler:^(CGImageRef image, NSError *captureError) {
                CGImageRef retained = image ? CGImageRetain(image) : NULL;
                dispatch_async(dispatch_get_main_queue(), ^{
                    ZMRCaptureComplete(context, callback, requestID, retained, descriptor,
                                       retained ? 0 : ZMRErrorCaptureFailed,
                                       retained ? nil : @"无法截取当前显示器");
                });
            }];
        }];
    });
}

void zmr_image_release(void *image) { if (image) CGImageRelease((CGImageRef)image); }

@interface ZMRWorkspaceWindow : NSWindow
@end
@implementation ZMRWorkspaceWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

@interface ZMRZoomView : NSView
@property(nonatomic) CGImageRef image;
@property(nonatomic) double scale;
@property(nonatomic) NSPoint offset;
@property(nonatomic) void *callbackContext;
@property(nonatomic) zmr_window_callbacks callbacks;
@property(nonatomic, strong) NSTextField *hud;
@property(nonatomic) NSPoint previousDragPoint;
@property(nonatomic, strong) NSTrackingArea *trackingArea;
@property(nonatomic) BOOL spotlightActive;
@property(nonatomic) NSPoint spotlightCenter;
@end

@implementation ZMRZoomView
- (instancetype)initWithFrame:(NSRect)frame image:(CGImageRef)image context:(void *)context callbacks:(zmr_window_callbacks)callbacks {
    if ((self = [super initWithFrame:frame])) {
        _image = image; // ownership is transferred into the view
        _scale = 1.0;
        _callbackContext = context;
        _callbacks = callbacks;
        self.wantsLayer = YES;
        _hud = [NSTextField labelWithString:@"100%"];
        _hud.font = [NSFont monospacedDigitSystemFontOfSize:18 weight:NSFontWeightSemibold];
        _hud.textColor = NSColor.whiteColor;
        _hud.alignment = NSTextAlignmentCenter;
        _hud.wantsLayer = YES;
        _hud.layer.backgroundColor = [NSColor colorWithWhite:0 alpha:0.72].CGColor;
        _hud.layer.cornerRadius = 7;
        [self addSubview:_hud];
    }
    return self;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isFlipped { return NO; }
- (void)layout {
    [super layout];
    self.hud.frame = NSMakeRect(16, 16, 88, 36);
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.trackingArea) [self removeTrackingArea:self.trackingArea];
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
        options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:self.trackingArea];
}
- (void)mouseEntered:(NSEvent *)event { [NSCursor.openHandCursor push]; }
- (void)mouseExited:(NSEvent *)event { [NSCursor pop]; }
- (void)mouseMoved:(NSEvent *)event {
    if (!self.spotlightActive) return;
    self.spotlightCenter = [self convertPoint:event.locationInWindow fromView:nil];
    [self setNeedsDisplay:YES];
}
- (void)mouseDown:(NSEvent *)event {
    self.previousDragPoint = [self convertPoint:event.locationInWindow fromView:nil];
    [NSCursor.closedHandCursor set];
}
- (void)mouseDragged:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.spotlightActive) {
        self.spotlightCenter = point;
        [self setNeedsDisplay:YES];
    }
    if (self.callbacks.pan_requested)
        self.callbacks.pan_requested(self.callbackContext, point.x - self.previousDragPoint.x,
                                     point.y - self.previousDragPoint.y);
    self.previousDragPoint = point;
}
- (void)mouseUp:(NSEvent *)event { [NSCursor.openHandCursor set]; }
- (void)scrollWheel:(NSEvent *)event {
    if (event.hasPreciseScrollingDeltas) {
        if (self.callbacks.pan_requested)
            // Move content opposite to the trackpad gesture on both axes.
            self.callbacks.pan_requested(self.callbackContext, event.scrollingDeltaX,
                                         -event.scrollingDeltaY);
        return;
    }

    NSPoint anchor = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.callbacks.zoom_requested)
        self.callbacks.zoom_requested(self.callbackContext, event.scrollingDeltaY, anchor.x, anchor.y);
}
- (void)magnifyWithEvent:(NSEvent *)event {
    NSPoint anchor = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.callbacks.magnify_requested)
        self.callbacks.magnify_requested(self.callbackContext, event.magnification, anchor.x, anchor.y);
}
- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 3) {
        if (!self.spotlightActive) {
            self.spotlightActive = YES;
            self.spotlightCenter = [self convertPoint:self.window.mouseLocationOutsideOfEventStream
                                              fromView:nil];
            [self setNeedsDisplay:YES];
        }
        return;
    }
    if (event.keyCode == 53) {
        if (self.callbacks.dismiss_requested) self.callbacks.dismiss_requested(self.callbackContext);
        return;
    }
    if ((event.modifierFlags & NSEventModifierFlagCommand) && event.keyCode == 29) {
        if (self.callbacks.reset_requested) self.callbacks.reset_requested(self.callbackContext);
        return;
    }
    [super keyDown:event];
}
- (void)keyUp:(NSEvent *)event {
    if (event.keyCode == 3) {
        if (self.spotlightActive) {
            self.spotlightActive = NO;
            [self setNeedsDisplay:YES];
        }
        return;
    }
    [super keyUp:event];
}
- (BOOL)resignFirstResponder {
    if (self.spotlightActive) {
        self.spotlightActive = NO;
        [self setNeedsDisplay:YES];
    }
    return [super resignFirstResponder];
}
- (void)showHUD {
    self.hud.stringValue = [NSString stringWithFormat:@"%.0f%%", self.scale * 100.0];
    self.hud.alphaValue = 1.0;
    [self.hud.layer removeAllAnimations];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fadeHUD) object:nil];
    [self performSelector:@selector(fadeHUD) withObject:nil afterDelay:0.8];
}
- (void)fadeHUD {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *animation) {
        animation.duration = 0.2;
        self.hud.animator.alphaValue = 0.0;
    } completionHandler:nil];
}
- (void)drawRect:(NSRect)dirtyRect {
    [NSColor.blackColor setFill];
    NSRectFill(self.bounds);
    if (!self.image) return;
    NSRect destination = NSMakeRect(self.offset.x, self.offset.y,
                                    NSWidth(self.bounds) * self.scale,
                                    NSHeight(self.bounds) * self.scale);
    CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
    CGContextSetInterpolationQuality(cg, kCGInterpolationHigh);
    CGContextDrawImage(cg, NSRectToCGRect(destination), self.image);

    if (self.spotlightActive) {
        static const CGFloat radius = 90.0;
        static CGGradientRef gradient;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            static const CGFloat components[] = {
                0.0, 0.0,
                0.0, 0.0,
                0.0, 0.72,
            };
            static const CGFloat locations[] = { 0.0, 0.72, 1.0 };
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
            gradient = CGGradientCreateWithColorComponents(
                colorSpace, components, locations, 3);
            CGColorSpaceRelease(colorSpace);
        });

        CGContextSaveGState(cg);
        CGContextDrawRadialGradient(cg, gradient, self.spotlightCenter, 0.0,
                                    self.spotlightCenter, radius,
                                    kCGGradientDrawsAfterEndLocation);
        CGContextRestoreGState(cg);
    }
}
- (void)dealloc { if (_image) CGImageRelease(_image); }
@end

@interface ZMRWindowBox : NSObject
@property(nonatomic, strong) ZMRWorkspaceWindow *window;
@property(nonatomic, strong) ZMRZoomView *view;
@property(nonatomic) CGDirectDisplayID displayID;
@property(nonatomic, strong) id screenObserver;
@property(nonatomic, strong) id spaceObserver;
@property(nonatomic, strong) id keyObserver;
@end
@implementation ZMRWindowBox
@end

static void ZMRCheckDisplay(ZMRWindowBox *box) {
    for (NSScreen *screen in NSScreen.screens) {
        if ([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == box.displayID) return;
    }
    if (box.view.callbacks.display_disconnected)
        box.view.callbacks.display_disconnected(box.view.callbackContext);
}

void *zmr_window_create(void *context, zmr_window_callbacks callbacks,
                        void *image, zmr_display_descriptor display) {
    if (!image || !NSThread.isMainThread) return NULL;
    NSScreen *target = nil;
    for (NSScreen *screen in NSScreen.screens) {
        if ([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == display.display_id) {
            target = screen; break;
        }
    }
    if (!target) return NULL;
    NSRect frame = target.frame;
    ZMRWorkspaceWindow *window = [[ZMRWorkspaceWindow alloc] initWithContentRect:frame
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO screen:target];
    window.backgroundColor = NSColor.blackColor;
    window.opaque = YES;
    window.acceptsMouseMovedEvents = YES;
    window.level = NSMainMenuWindowLevel;
    window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    window.releasedWhenClosed = NO;
    ZMRZoomView *view = [[ZMRZoomView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)
        image:(CGImageRef)image context:context callbacks:callbacks];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    window.contentView = view;
    ZMRWindowBox *box = [[ZMRWindowBox alloc] init];
    box.window = window;
    box.view = view;
    box.displayID = display.display_id;
    __weak ZMRWindowBox *weakBox = box;
    box.screenObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidChangeScreenParametersNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        ZMRWindowBox *strongBox = weakBox; if (strongBox) ZMRCheckDisplay(strongBox);
    }];
    box.spaceObserver = [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        ZMRWindowBox *strongBox = weakBox; if (strongBox) ZMRCheckDisplay(strongBox);
    }];
    box.keyObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidResignKeyNotification
        object:window queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        ZMRWindowBox *strongBox = weakBox;
        if (strongBox && strongBox.view.spotlightActive) {
            strongBox.view.spotlightActive = NO;
            [strongBox.view setNeedsDisplay:YES];
        }
    }];
    return (__bridge_retained void *)box;
}

void zmr_window_show(void *handle) {
    ZMRWindowBox *box = (__bridge ZMRWindowBox *)handle;
    if (!box) return;
    [NSApplication.sharedApplication activateIgnoringOtherApps:YES];
    [box.window makeKeyAndOrderFront:nil];
    [box.window makeFirstResponder:box.view];
}

void zmr_window_update_transform(void *handle, double scale, double offsetX,
                                 double offsetY, bool showHUD) {
    ZMRWindowBox *box = (__bridge ZMRWindowBox *)handle;
    if (!box) return;
    box.view.scale = scale;
    box.view.offset = NSMakePoint(offsetX, offsetY);
    [box.view setNeedsDisplay:YES];
    if (showHUD) [box.view showHUD];
}

void zmr_window_destroy(void *handle) {
    if (!handle) return;
    ZMRWindowBox *box = (__bridge_transfer ZMRWindowBox *)handle;
    if (box.screenObserver) [NSNotificationCenter.defaultCenter removeObserver:box.screenObserver];
    if (box.spaceObserver) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:box.spaceObserver];
    if (box.keyObserver) [NSNotificationCenter.defaultCenter removeObserver:box.keyObserver];
    box.view.callbacks = (zmr_window_callbacks){0};
    [box.window close];
    box.window = nil;
    box.view = nil;
}
