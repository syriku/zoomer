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

static const CFTimeInterval ZMRLaserDrawingHoldDuration = 3.0;
static const CFTimeInterval ZMRLaserDrawingFadeDuration = 0.8;
static const CGFloat ZMRLaserDrawingMinimumPointDistanceSquared = 0.25;

@interface ZMRLaserStroke : NSObject
@property(nonatomic, strong) NSMutableArray<NSValue *> *points;
@property(nonatomic) CFTimeInterval releasedAt;
- (instancetype)initWithPoint:(NSPoint)point;
@end

@implementation ZMRLaserStroke
- (instancetype)initWithPoint:(NSPoint)point {
    if ((self = [super init])) {
        _points = [NSMutableArray arrayWithObject:[NSValue valueWithPoint:point]];
    }
    return self;
}
@end

@interface ZMRZoomView : NSView
@property(nonatomic) CGImageRef image;
@property(nonatomic) double scale;
@property(nonatomic) NSPoint offset;
@property(nonatomic) BOOL horizontallyFlipped;
@property(nonatomic) void *callbackContext;
@property(nonatomic) zmr_window_callbacks callbacks;
@property(nonatomic, strong) NSTextField *hud;
@property(nonatomic) NSPoint previousDragPoint;
@property(nonatomic, strong) NSTrackingArea *trackingArea;
@property(nonatomic) BOOL spotlightActive;
@property(nonatomic) NSPoint spotlightCenter;
@property(nonatomic) BOOL laserPointerVisible;
@property(nonatomic) NSPoint laserPointerCenter;
@property(nonatomic) BOOL systemCursorHidden;
@property(nonatomic) BOOL laserDrawingMode;
@property(nonatomic, strong) ZMRLaserStroke *activeLaserStroke;
@property(nonatomic, strong) NSMutableArray<ZMRLaserStroke *> *laserStrokes;
@property(nonatomic, strong) NSTimer *laserTrailTimer;
- (void)hideSystemCursor;
- (void)restoreSystemCursor;
- (void)endActiveLaserStroke;
- (void)clearLaserStrokes;
@end

@implementation ZMRZoomView
- (instancetype)initWithFrame:(NSRect)frame image:(CGImageRef)image context:(void *)context callbacks:(zmr_window_callbacks)callbacks {
    if ((self = [super initWithFrame:frame])) {
        _image = image; // ownership is transferred into the view
        _scale = 1.0;
        _callbackContext = context;
        _callbacks = callbacks;
        _laserStrokes = [NSMutableArray array];
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
- (void)hideSystemCursor {
    if (self.systemCursorHidden) return;
    [NSCursor hide];
    self.systemCursorHidden = YES;
}
- (void)restoreSystemCursor {
    if (!self.systemCursorHidden) return;
    [NSCursor unhide];
    self.systemCursorHidden = NO;
}
- (void)beginLaserStrokeAtPoint:(NSPoint)point {
    ZMRLaserStroke *stroke = [[ZMRLaserStroke alloc] initWithPoint:point];
    [self.laserStrokes addObject:stroke];
    self.activeLaserStroke = stroke;
}
- (NSPoint)canvasPointForViewPoint:(NSPoint)point {
    double scale = self.scale;
    if (scale <= 0.0) return point;

    double x = (point.x - self.offset.x) / scale;
    if (self.horizontallyFlipped) x = NSWidth(self.bounds) - x;
    return NSMakePoint(x, (point.y - self.offset.y) / scale);
}
- (NSPoint)viewPointForCanvasPoint:(NSPoint)point {
    double x = point.x;
    if (self.horizontallyFlipped) x = NSWidth(self.bounds) - x;
    return NSMakePoint(self.offset.x + (x * self.scale),
                       self.offset.y + (point.y * self.scale));
}
- (void)appendLaserStrokePoint:(NSPoint)point {
    ZMRLaserStroke *stroke = self.activeLaserStroke;
    if (!stroke) return;

    NSPoint previous = stroke.points.lastObject.pointValue;
    CGFloat deltaX = point.x - previous.x;
    CGFloat deltaY = point.y - previous.y;
    CGFloat minimumDistanceSquared = ZMRLaserDrawingMinimumPointDistanceSquared /
        ((CGFloat)self.scale * (CGFloat)self.scale);
    if ((deltaX * deltaX) + (deltaY * deltaY) < minimumDistanceSquared)
        return;

    [stroke.points addObject:[NSValue valueWithPoint:point]];
}
- (void)startLaserTrailTimer {
    if (self.laserTrailTimer) return;

    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:(1.0 / 60.0) repeats:YES
        block:^(NSTimer *firedTimer) {
        ZMRZoomView *strongSelf = weakSelf;
        if (!strongSelf) {
            [firedTimer invalidate];
            return;
        }
        [strongSelf updateLaserTrails];
    }];
    self.laserTrailTimer = timer;
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
}
- (void)updateLaserTrails {
    CFTimeInterval now = CACurrentMediaTime();
    BOOL keepTimer = NO;
    BOOL needsRedraw = NO;
    for (NSInteger index = (NSInteger)self.laserStrokes.count - 1; index >= 0; index--) {
        ZMRLaserStroke *stroke = self.laserStrokes[(NSUInteger)index];
        if (stroke.releasedAt <= 0.0) continue;

        CFTimeInterval elapsed = now - stroke.releasedAt;
        if (elapsed >= ZMRLaserDrawingHoldDuration + ZMRLaserDrawingFadeDuration) {
            [self.laserStrokes removeObjectAtIndex:(NSUInteger)index];
            needsRedraw = YES;
            continue;
        }

        keepTimer = YES;
        if (elapsed >= ZMRLaserDrawingHoldDuration)
            needsRedraw = YES;
    }
    if (needsRedraw) [self setNeedsDisplay:YES];
    if (!keepTimer) {
        [self.laserTrailTimer invalidate];
        self.laserTrailTimer = nil;
    }
}
- (void)endActiveLaserStroke {
    ZMRLaserStroke *stroke = self.activeLaserStroke;
    if (!stroke) return;

    stroke.releasedAt = CACurrentMediaTime();
    self.activeLaserStroke = nil;
    [self startLaserTrailTimer];
    [self setNeedsDisplay:YES];
}
- (void)clearLaserStrokes {
    [self.laserTrailTimer invalidate];
    self.laserTrailTimer = nil;
    self.activeLaserStroke = nil;
    [self.laserStrokes removeAllObjects];
}
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
- (void)mouseEntered:(NSEvent *)event {
    [NSCursor.openHandCursor push];
    [self hideSystemCursor];
    self.laserPointerVisible = YES;
    self.laserPointerCenter = [self convertPoint:event.locationInWindow fromView:nil];
    [self setNeedsDisplay:YES];
}
- (void)mouseExited:(NSEvent *)event {
    [self restoreSystemCursor];
    [NSCursor pop];
    self.laserPointerVisible = NO;
    [self setNeedsDisplay:YES];
}
- (void)mouseMoved:(NSEvent *)event {
    [self hideSystemCursor];
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    self.laserPointerVisible = YES;
    self.laserPointerCenter = point;
    if (self.spotlightActive) self.spotlightCenter = point;
    [self setNeedsDisplay:YES];
}
- (void)mouseDown:(NSEvent *)event {
    [self hideSystemCursor];
    [self endActiveLaserStroke];
    self.previousDragPoint = [self convertPoint:event.locationInWindow fromView:nil];
    self.laserPointerVisible = YES;
    self.laserPointerCenter = self.previousDragPoint;
    [self setNeedsDisplay:YES];
    if (self.laserDrawingMode) {
        [self beginLaserStrokeAtPoint:[self canvasPointForViewPoint:self.previousDragPoint]];
    } else {
        [NSCursor.closedHandCursor set];
    }
}
- (void)mouseDragged:(NSEvent *)event {
    [self hideSystemCursor];
    if (self.activeLaserStroke) {
        NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        [self appendLaserStrokePoint:[self canvasPointForViewPoint:point]];
        self.laserPointerCenter = point;
        if (self.spotlightActive) self.spotlightCenter = point;
        self.laserPointerVisible = YES;
        [self setNeedsDisplay:YES];
        return;
    }

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    self.laserPointerVisible = YES;
    self.laserPointerCenter = point;
    if (self.spotlightActive) {
        self.spotlightCenter = point;
    }
    [self setNeedsDisplay:YES];
    if (self.callbacks.pan_requested)
        self.callbacks.pan_requested(self.callbackContext, point.x - self.previousDragPoint.x,
                                     point.y - self.previousDragPoint.y);
    self.previousDragPoint = point;
}
- (void)mouseUp:(NSEvent *)event {
    if (self.activeLaserStroke) {
        NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        [self appendLaserStrokePoint:[self canvasPointForViewPoint:point]];
        self.laserPointerCenter = point;
        if (self.spotlightActive) self.spotlightCenter = point;
        [self endActiveLaserStroke];
    } else {
        [NSCursor.openHandCursor set];
    }
}
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
- (void)requestPresetScale:(double)scale forEvent:(NSEvent *)event {
    if (!self.callbacks.magnify_requested) return;
    NSPoint anchor = [self convertPoint:event.locationInWindow fromView:nil];
    self.callbacks.magnify_requested(self.callbackContext, scale - self.scale, anchor.x, anchor.y);
}
- (void)keyDown:(NSEvent *)event {
    NSEventModifierFlags modifiers = event.modifierFlags &
        (NSEventModifierFlagCommand | NSEventModifierFlagOption |
         NSEventModifierFlagControl | NSEventModifierFlagShift);
    BOOL hasShortcutModifier = modifiers != 0;
    BOOL isZero = event.keyCode == kVK_ANSI_0 || event.keyCode == kVK_ANSI_Keypad0;
    if (!event.isARepeat && isZero &&
        (modifiers == 0 || modifiers == NSEventModifierFlagCommand)) {
        if (self.callbacks.reset_requested) self.callbacks.reset_requested(self.callbackContext);
        return;
    }
    if (!event.isARepeat && !hasShortcutModifier) {
        double presetScale = 0.0;
        switch (event.keyCode) {
            case kVK_ANSI_1:
            case kVK_ANSI_Keypad1:
                presetScale = 1.5;
                break;
            case kVK_ANSI_2:
            case kVK_ANSI_Keypad2:
                presetScale = 2.0;
                break;
            case kVK_ANSI_9:
            case kVK_ANSI_Keypad9:
                presetScale = 0.7;
                break;
        }
        if (presetScale > 0.0) {
            [self requestPresetScale:presetScale forEvent:event];
            return;
        }
    }
    if (!event.isARepeat && !hasShortcutModifier && event.keyCode == kVK_ANSI_D) {
        self.laserDrawingMode = !self.laserDrawingMode;
        return;
    }
    if (event.keyCode == kVK_ANSI_M) {
        if (!event.isARepeat && self.callbacks.toggle_horizontal_flip_requested)
            self.callbacks.toggle_horizontal_flip_requested(self.callbackContext);
        return;
    }
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
    [self restoreSystemCursor];
    [self endActiveLaserStroke];
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
- (void)drawLaserStrokesInContext:(CGContextRef)context {
    CFTimeInterval now = CACurrentMediaTime();
    CGFloat drawingScale = (CGFloat)self.scale;
    NSRect destination = NSMakeRect(self.offset.x, self.offset.y,
                                    NSWidth(self.bounds) * drawingScale,
                                    NSHeight(self.bounds) * drawingScale);
    CGContextSaveGState(context);
    CGContextClipToRect(context, NSRectToCGRect(destination));
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    for (ZMRLaserStroke *stroke in self.laserStrokes) {
        NSArray<NSValue *> *points = stroke.points;
        if (points.count == 0) continue;

        CGFloat opacity = 1.0;
        if (stroke.releasedAt > 0.0) {
            CFTimeInterval elapsed = now - stroke.releasedAt;
            if (elapsed > ZMRLaserDrawingHoldDuration) {
                opacity = MAX(0.0, 1.0 - ((elapsed - ZMRLaserDrawingHoldDuration) /
                                          ZMRLaserDrawingFadeDuration));
            }
        }
        if (opacity <= 0.0) continue;

        if (points.count == 1) {
            NSPoint point = [self viewPointForCanvasPoint:points.firstObject.pointValue];
            CGContextSetFillColorWithColor(context,
                [NSColor colorWithCalibratedRed:1.0 green:0.08 blue:0.08 alpha:0.28 * opacity].CGColor);
            CGContextFillEllipseInRect(context, CGRectMake(point.x - (3.5 * drawingScale),
                                                           point.y - (3.5 * drawingScale),
                                                           7.0 * drawingScale, 7.0 * drawingScale));
            CGContextSetFillColorWithColor(context,
                [NSColor colorWithCalibratedRed:1.0 green:0.05 blue:0.05 alpha:0.96 * opacity].CGColor);
            CGContextFillEllipseInRect(context, CGRectMake(point.x - (1.75 * drawingScale),
                                                           point.y - (1.75 * drawingScale),
                                                           3.5 * drawingScale, 3.5 * drawingScale));
            continue;
        }

        CGMutablePathRef path = CGPathCreateMutable();
        NSPoint first = [self viewPointForCanvasPoint:points.firstObject.pointValue];
        CGPathMoveToPoint(path, NULL, first.x, first.y);
        for (NSUInteger index = 1; index < points.count; index++) {
            NSPoint point = [self viewPointForCanvasPoint:points[index].pointValue];
            CGPathAddLineToPoint(path, NULL, point.x, point.y);
        }

        CGContextAddPath(context, path);
        CGContextSetStrokeColorWithColor(context,
            [NSColor colorWithCalibratedRed:1.0 green:0.08 blue:0.08 alpha:0.28 * opacity].CGColor);
        CGContextSetLineWidth(context, 7.0 * drawingScale);
        CGContextStrokePath(context);
        CGContextAddPath(context, path);
        CGContextSetStrokeColorWithColor(context,
            [NSColor colorWithCalibratedRed:1.0 green:0.05 blue:0.05 alpha:0.96 * opacity].CGColor);
        CGContextSetLineWidth(context, 3.5 * drawingScale);
        CGContextStrokePath(context);
        CGPathRelease(path);
    }
    CGContextRestoreGState(context);
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
    if (self.horizontallyFlipped) {
        CGContextSaveGState(cg);
        CGContextTranslateCTM(cg, NSMinX(destination) + NSMaxX(destination), 0);
        CGContextScaleCTM(cg, -1, 1);
    }
    CGContextDrawImage(cg, NSRectToCGRect(destination), self.image);
    if (self.horizontallyFlipped) CGContextRestoreGState(cg);

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

    [self drawLaserStrokesInContext:cg];

    if (self.laserPointerVisible) {
        static const CGFloat outerRadius = 11.0;
        static const CGFloat coreRadius = 4.0;
        NSPoint center = self.laserPointerCenter;
        CGContextSaveGState(cg);
        CGContextSetFillColorWithColor(cg,
            [NSColor colorWithCalibratedRed:1.0 green:0.08 blue:0.08 alpha:0.28].CGColor);
        CGContextFillEllipseInRect(cg, CGRectMake(center.x - outerRadius, center.y - outerRadius,
                                                   outerRadius * 2.0, outerRadius * 2.0));
        CGContextSetFillColorWithColor(cg,
            [NSColor colorWithCalibratedRed:1.0 green:0.05 blue:0.05 alpha:0.96].CGColor);
        CGContextFillEllipseInRect(cg, CGRectMake(center.x - coreRadius, center.y - coreRadius,
                                                   coreRadius * 2.0, coreRadius * 2.0));
        CGContextSetStrokeColorWithColor(cg, [NSColor.whiteColor colorWithAlphaComponent:0.9].CGColor);
        CGContextSetLineWidth(cg, 1.0);
        CGContextStrokeEllipseInRect(cg, CGRectMake(center.x - coreRadius, center.y - coreRadius,
                                                     coreRadius * 2.0, coreRadius * 2.0));
        CGContextRestoreGState(cg);
    }
}
- (void)dealloc {
    [self clearLaserStrokes];
    [self restoreSystemCursor];
    if (_image) CGImageRelease(_image);
}
@end

@interface ZMRWindowBox : NSObject
@property(nonatomic, strong) ZMRWorkspaceWindow *window;
@property(nonatomic, strong) ZMRZoomView *view;
@property(nonatomic) CGDirectDisplayID displayID;
@property(nonatomic, strong) id screenObserver;
@property(nonatomic, strong) id spaceObserver;
@property(nonatomic, strong) id keyObserver;
@property(nonatomic, strong) id becameKeyObserver;
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
        if (strongBox) {
            [strongBox.view restoreSystemCursor];
            [strongBox.view endActiveLaserStroke];
            if (strongBox.view.spotlightActive) {
                strongBox.view.spotlightActive = NO;
                [strongBox.view setNeedsDisplay:YES];
            }
        }
    }];
    box.becameKeyObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeKeyNotification
        object:window queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        ZMRWindowBox *strongBox = weakBox;
        if (!strongBox) return;
        NSPoint point = [strongBox.view convertPoint:strongBox.window.mouseLocationOutsideOfEventStream
                                           fromView:nil];
        if (NSPointInRect(point, strongBox.view.bounds)) [strongBox.view hideSystemCursor];
    }];
    return (__bridge_retained void *)box;
}

void zmr_window_show(void *handle) {
    ZMRWindowBox *box = (__bridge ZMRWindowBox *)handle;
    if (!box) return;
    [NSApplication.sharedApplication activateIgnoringOtherApps:YES];
    [box.window makeKeyAndOrderFront:nil];
    [box.window makeFirstResponder:box.view];
    box.view.laserPointerCenter = [box.view convertPoint:box.window.mouseLocationOutsideOfEventStream
                                                fromView:nil];
    box.view.laserPointerVisible = NSPointInRect(box.view.laserPointerCenter, box.view.bounds);
    if (box.view.laserPointerVisible) [box.view hideSystemCursor];
    [box.view setNeedsDisplay:YES];
}

void zmr_window_update_transform(void *handle, double scale, double offsetX,
                                  double offsetY, bool horizontallyFlipped,
                                  bool showHUD) {
    ZMRWindowBox *box = (__bridge ZMRWindowBox *)handle;
    if (!box) return;
    box.view.scale = scale;
    box.view.offset = NSMakePoint(offsetX, offsetY);
    box.view.horizontallyFlipped = horizontallyFlipped;
    [box.view setNeedsDisplay:YES];
    if (showHUD) [box.view showHUD];
}

void zmr_window_destroy(void *handle) {
    if (!handle) return;
    ZMRWindowBox *box = (__bridge_transfer ZMRWindowBox *)handle;
    if (box.screenObserver) [NSNotificationCenter.defaultCenter removeObserver:box.screenObserver];
    if (box.spaceObserver) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:box.spaceObserver];
    if (box.keyObserver) [NSNotificationCenter.defaultCenter removeObserver:box.keyObserver];
    if (box.becameKeyObserver) [NSNotificationCenter.defaultCenter removeObserver:box.becameKeyObserver];
    [box.view restoreSystemCursor];
    [box.view clearLaserStrokes];
    box.view.callbacks = (zmr_window_callbacks){0};
    [box.window close];
    box.window = nil;
    box.view = nil;
}
