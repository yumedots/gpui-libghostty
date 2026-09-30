#import <AppKit/AppKit.h>
#import <CoreVideo/CoreVideo.h>
#import <IOSurface/IOSurface.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <stdlib.h>
#import <string.h>
#import <ghostty.h>

@interface GpuiGhosttyView : NSView
@end

@implementation GpuiGhosttyView
- (NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}
@end

static char gpui_ghostty_overlay_key;

@interface GpuiGhosttyOverlayView : NSView
@property (nonatomic, assign) CALayer *preview_layer;
@property (nonatomic, assign) CALayer *pill_layer;
@property (nonatomic, assign) uint32_t preview_color;
@property (nonatomic, assign) uint32_t pill_background;
@property (nonatomic, assign) uint32_t pill_border;
@property (nonatomic, assign) uint32_t pill_dot;
@end

@implementation GpuiGhosttyOverlayView
- (NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}
@end

static NSColor *gpui_ghostty_overlay_color(uint32_t rgba) {
    CGFloat red = ((rgba >> 24) & 0xff) / 255.0;
    CGFloat green = ((rgba >> 16) & 0xff) / 255.0;
    CGFloat blue = ((rgba >> 8) & 0xff) / 255.0;
    CGFloat alpha = (rgba & 0xff) / 255.0;
    return [NSColor colorWithSRGBRed:red green:green blue:blue alpha:alpha];
}

static void gpui_ghostty_overlay_hide_preview(GpuiGhosttyOverlayView *overlay) {
    if (overlay == nil || overlay.preview_layer.hidden) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    overlay.preview_layer.hidden = YES;
    overlay.preview_color = 0;
    [CATransaction commit];
}

static void gpui_ghostty_overlay_hide_pill(GpuiGhosttyOverlayView *overlay) {
    if (overlay == nil || overlay.pill_layer.hidden) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    overlay.pill_layer.hidden = YES;
    overlay.pill_background = 0;
    overlay.pill_border = 0;
    overlay.pill_dot = 0;
    [CATransaction commit];
}

static void gpui_ghostty_overlay_hide(GpuiGhosttyOverlayView *overlay) {
    gpui_ghostty_overlay_hide_preview(overlay);
    gpui_ghostty_overlay_hide_pill(overlay);
}

static void gpui_ghostty_overlay_layout_pill(GpuiGhosttyOverlayView *overlay, NSRect frame) {
    overlay.pill_layer.frame = frame;
    CGFloat width = NSWidth(frame);
    CGFloat height = NSHeight(frame);
    NSArray<CALayer *> *dots = overlay.pill_layer.sublayers;
    for (NSUInteger index = 0; index < dots.count; index++) {
        CGFloat center = width / 2.0 + ((CGFloat)index - 1.0) * 7.0;
        dots[index].frame = NSMakeRect(center - 2.0, height / 2.0 - 2.0, 4.0, 4.0);
    }
}

static void gpui_ghostty_overlay_paint_pill_colors(GpuiGhosttyOverlayView *overlay) {
    overlay.pill_layer.backgroundColor = gpui_ghostty_overlay_color(overlay.pill_background).CGColor;
    overlay.pill_layer.borderColor = gpui_ghostty_overlay_color(overlay.pill_border).CGColor;
    NSColor *dot = gpui_ghostty_overlay_color(overlay.pill_dot);
    for (CALayer *layer in overlay.pill_layer.sublayers) {
        layer.backgroundColor = dot.CGColor;
    }
}

static GpuiGhosttyOverlayView *gpui_ghostty_overlay_front(NSView *parent) {
    if (parent == nil) return nil;
    GpuiGhosttyOverlayView *overlay = objc_getAssociatedObject(parent, &gpui_ghostty_overlay_key);
    BOOL fresh = overlay == nil;
    if (fresh) {
        overlay = [[GpuiGhosttyOverlayView alloc]
            initWithFrame:NSMakeRect(0, 0, NSWidth(parent.bounds), NSHeight(parent.bounds))];
        overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        overlay.wantsLayer = YES;
        overlay.layer = [CALayer layer];
        CALayer *preview = [CALayer layer];
        preview.hidden = YES;
        [overlay.layer addSublayer:preview];
        overlay.preview_layer = preview;
        CALayer *pill = [CALayer layer];
        pill.hidden = YES;
        pill.cornerRadius = 5.0;
        pill.borderWidth = 1.0;
        pill.masksToBounds = YES;
        [overlay.layer addSublayer:pill];
        for (NSUInteger index = 0; index < 3; index++) {
            CALayer *dot = [CALayer layer];
            dot.cornerRadius = 2.0;
            [pill addSublayer:dot];
        }
        overlay.pill_layer = pill;
    }
    [parent addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
    if (fresh) {
        objc_setAssociatedObject(
            parent, &gpui_ghostty_overlay_key, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [overlay release];
    }
    return overlay;
}

static GpuiGhosttyOverlayView *gpui_ghostty_overlay_for(NSView *parent) {
    if (parent == nil) return nil;
    return objc_getAssociatedObject(parent, &gpui_ghostty_overlay_key);
}

void gpui_ghostty_overlay_preview(
    void *parent_view,
    double x,
    double y,
    double width,
    double height,
    uint32_t rgba
) {
    NSView *parent = (NSView *)parent_view;
    GpuiGhosttyOverlayView *overlay = gpui_ghostty_overlay_front(parent);
    if (overlay == nil) return;
    if (width <= 0.0 || height <= 0.0) {
        gpui_ghostty_overlay_hide_preview(overlay);
        return;
    }
    NSRect frame = NSMakeRect(x, NSHeight(overlay.bounds) - y - height, width, height);
    BOOL hidden = overlay.preview_layer.hidden;
    BOOL moved = !CGRectEqualToRect(overlay.preview_layer.frame, frame);
    BOOL recolored = overlay.preview_color != rgba;
    if (!hidden && !moved && !recolored) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (hidden) {
        overlay.preview_layer.frame = frame;
        overlay.preview_layer.backgroundColor = gpui_ghostty_overlay_color(rgba).CGColor;
        overlay.preview_color = rgba;
        overlay.preview_layer.hidden = NO;
    } else {
        if (moved) overlay.preview_layer.frame = frame;
        if (recolored) {
            overlay.preview_layer.backgroundColor = gpui_ghostty_overlay_color(rgba).CGColor;
            overlay.preview_color = rgba;
        }
    }
    [CATransaction commit];
}

void gpui_ghostty_overlay_pill(
    void *parent_view,
    double x,
    double y,
    double width,
    double height,
    uint32_t background,
    uint32_t border,
    uint32_t dot
) {
    NSView *parent = (NSView *)parent_view;
    GpuiGhosttyOverlayView *overlay = gpui_ghostty_overlay_front(parent);
    if (overlay == nil) return;
    if (width <= 0.0 || height <= 0.0) {
        gpui_ghostty_overlay_hide_pill(overlay);
        return;
    }
    NSRect frame = NSMakeRect(x, NSHeight(overlay.bounds) - y - height, width, height);
    BOOL hidden = overlay.pill_layer.hidden;
    BOOL moved = !CGRectEqualToRect(overlay.pill_layer.frame, frame);
    BOOL recolored = overlay.pill_background != background || overlay.pill_border != border
        || overlay.pill_dot != dot;
    if (!hidden && !moved && !recolored) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (hidden) {
        gpui_ghostty_overlay_layout_pill(overlay, frame);
        overlay.pill_background = background;
        overlay.pill_border = border;
        overlay.pill_dot = dot;
        gpui_ghostty_overlay_paint_pill_colors(overlay);
        overlay.pill_layer.hidden = NO;
    } else {
        if (moved) gpui_ghostty_overlay_layout_pill(overlay, frame);
        if (recolored) {
            overlay.pill_background = background;
            overlay.pill_border = border;
            overlay.pill_dot = dot;
            gpui_ghostty_overlay_paint_pill_colors(overlay);
        }
    }
    [CATransaction commit];
}

typedef void (*gpui_ghostty_wakeup_cb)(void *userdata);
// Adapter operation values: paste=0, read=1, write=2.
typedef bool (*gpui_ghostty_approve_clipboard_cb)(void *userdata, int operation, const char *text);

typedef struct gpui_ghostty_surface {
    ghostty_config_t config;
    ghostty_app_t app;
    ghostty_surface_t surface;
    NSView *parent;
    GpuiGhosttyView *view;
    void *wakeup_userdata;
    gpui_ghostty_wakeup_cb wakeup;
    gpui_ghostty_approve_clipboard_cb approve_clipboard;
    void *clipboard_request;
    ghostty_clipboard_e clipboard_location;
    bool visible;
    bool hidden_rendering;
    _Atomic bool alive;
    _Atomic uint64_t frame_count;
} gpui_ghostty_surface;

static void runtime_wakeup(void *userdata) {
    gpui_ghostty_surface *state = userdata;
    state->wakeup(state->wakeup_userdata);
}

static bool runtime_action(ghostty_app_t app, ghostty_target_s target, ghostty_action_s action) {
    (void)app;
    if (action.tag == GHOSTTY_ACTION_RENDER &&
        target.tag == GHOSTTY_TARGET_SURFACE &&
        target.target.surface != NULL) {
        gpui_ghostty_surface *state = ghostty_surface_userdata(target.target.surface);
        if (state != NULL) {
            atomic_fetch_add_explicit(&state->frame_count, 1, memory_order_release);
        }
        ghostty_surface_draw(target.target.surface);
        return true;
    }
    return false;
}

static bool runtime_read_clipboard(void *userdata, ghostty_clipboard_e location, void *request) {
    gpui_ghostty_surface *state = userdata;
    if (state->surface == NULL || state->clipboard_request != NULL) return false;
    state->clipboard_request = request;
    state->clipboard_location = location;
    runtime_wakeup(state);
    return true;
}

static void runtime_confirm_read_clipboard(
    void *userdata,
    const char *text,
    void *request,
    ghostty_clipboard_request_e kind
) {
    gpui_ghostty_surface *state = userdata;
    if (state->surface != NULL) {
        int operation = kind == GHOSTTY_CLIPBOARD_REQUEST_PASTE ? 0 : 1;
        bool approved = state->approve_clipboard != NULL &&
            state->approve_clipboard(state->wakeup_userdata, operation, text);
        // Completing with empty text releases Ghostty's request without exposing
        // clipboard contents or inserting an unsafe paste.
        ghostty_surface_complete_clipboard_request(state->surface, approved ? text : "", request, true);
    }
}

static void runtime_write_clipboard(
    void *userdata,
    ghostty_clipboard_e location,
    const ghostty_clipboard_content_s *content,
    size_t count,
    bool confirm
) {
    gpui_ghostty_surface *state = userdata;
    (void)location;
    for (size_t index = 0; index < count; index++) {
        if (strcmp(content[index].mime, "text/plain") != 0) continue;
        if (confirm && (state->approve_clipboard == NULL ||
            !state->approve_clipboard(state->wakeup_userdata, 2, content[index].data))) return;
        NSString *text = [NSString stringWithUTF8String:content[index].data];
        if (text == nil) return;
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard setString:text forType:NSPasteboardTypeString];
        return;
    }
}

static void runtime_close_surface(void *userdata, bool process_alive) {
    (void)process_alive;
    gpui_ghostty_surface *state = userdata;
    atomic_store_explicit(&state->alive, false, memory_order_release);
    runtime_wakeup(state);
}

gpui_ghostty_surface *gpui_ghostty_surface_new(
    void *parent_view,
    const char *working_directory,
    const char *command,
    bool load_user_config,
    const char *theme_config_path,
    bool quiet_login,
    void *wakeup_userdata,
    gpui_ghostty_wakeup_cb wakeup,
    gpui_ghostty_approve_clipboard_cb approve_clipboard
) {
    static dispatch_once_t once;
    static int init_result = -1;
    dispatch_once(&once, ^{
        setenv("GHOSTTY_LOG", "stderr", 0);
        init_result = ghostty_init(0, NULL);
    });
    if (init_result != GHOSTTY_SUCCESS || parent_view == NULL ||
        wakeup_userdata == NULL || wakeup == NULL) return NULL;

    gpui_ghostty_surface *state = calloc(1, sizeof(gpui_ghostty_surface));
    if (state == NULL) return NULL;
    atomic_init(&state->alive, true);
    state->wakeup_userdata = wakeup_userdata;
    state->wakeup = wakeup;
    state->approve_clipboard = approve_clipboard;
    state->parent = (NSView *)parent_view;
    state->view = [[GpuiGhosttyView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    [state->view setHidden:YES];
    [state->parent addSubview:state->view];
    gpui_ghostty_overlay_front(state->parent);

    state->config = ghostty_config_new();
    if (state->config == NULL) goto fail;
    if (load_user_config) {
        ghostty_config_load_default_files(state->config);
        ghostty_config_load_recursive_files(state->config);
    }
    if (theme_config_path != NULL) {
        ghostty_config_load_file(state->config, theme_config_path);
    }
    ghostty_config_finalize(state->config);

    ghostty_runtime_config_s runtime = {
        .userdata = state,
        .supports_selection_clipboard = false,
        .wakeup_cb = runtime_wakeup,
        .action_cb = runtime_action,
        .read_clipboard_cb = runtime_read_clipboard,
        .confirm_read_clipboard_cb = runtime_confirm_read_clipboard,
        .write_clipboard_cb = runtime_write_clipboard,
        .close_surface_cb = runtime_close_surface,
    };
    state->app = ghostty_app_new(&runtime, state->config);
    if (state->app == NULL) goto fail;

    ghostty_surface_config_s surface_config = ghostty_surface_config_new();
    surface_config.platform_tag = GHOSTTY_PLATFORM_MACOS;
    surface_config.platform.macos.nsview = state->view;
    surface_config.userdata = state;
    surface_config.scale_factor = state->parent.window.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor;
    ghostty_env_var_s environment[] = {
        { .key = "TERM", .value = "xterm-256color" },
        { .key = "COLORTERM", .value = "truecolor" },
        { .key = "TERM_PROGRAM", .value = "gpui-ghostty" },
        { .key = "GHOSTTY_QUIET_LOGIN", .value = "1" },
    };
    size_t environment_count = sizeof(environment) / sizeof(environment[0]);
    if (!quiet_login) environment_count -= 1;
    surface_config.working_directory = working_directory;
    surface_config.command = command;
    surface_config.env_vars = environment;
    surface_config.env_var_count = environment_count;
    surface_config.wait_after_command = false;
    surface_config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW;
    state->surface = ghostty_surface_new(state->app, &surface_config);
    if (state->surface == NULL) goto fail;

    ghostty_app_set_focus(state->app, false);
    ghostty_surface_set_focus(state->surface, false);
    return state;

fail:
    if (state->surface != NULL) ghostty_surface_free(state->surface);
    if (state->app != NULL) ghostty_app_free(state->app);
    if (state->config != NULL) ghostty_config_free(state->config);
    [state->view removeFromSuperview];
    [state->view release];
    free(state);
    return NULL;
}

void gpui_ghostty_surface_free(gpui_ghostty_surface *state) {
    if (state == NULL) return;
    gpui_ghostty_overlay_hide(gpui_ghostty_overlay_for(state->parent));
    [state->view removeFromSuperview];
    if (state->surface != NULL) ghostty_surface_free(state->surface);
    if (state->app != NULL) ghostty_app_free(state->app);
    if (state->config != NULL) ghostty_config_free(state->config);
    [state->view release];
    free(state);
}

void gpui_ghostty_surface_tick(gpui_ghostty_surface *state) {
    if (state == NULL || state->app == NULL) return;
    ghostty_app_tick(state->app);
}

bool gpui_ghostty_surface_is_alive(const gpui_ghostty_surface *state) {
    return state != NULL && atomic_load_explicit(&state->alive, memory_order_acquire)
        && !ghostty_surface_process_exited(state->surface);
}

// Counts the frames Ghostty has handed to this surface. A caller that applies a
// new configuration can wait for the count to move instead of guessing a delay.
uint64_t gpui_ghostty_surface_frame_count(gpui_ghostty_surface *state) {
    if (state == NULL) return 0;
    return atomic_load_explicit(&state->frame_count, memory_order_acquire);
}

bool gpui_ghostty_surface_update_theme(
    gpui_ghostty_surface *state,
    bool load_user_config,
    const char *theme_config_path
) {
    if (state == NULL || state->surface == NULL) return false;
    ghostty_config_t config = ghostty_config_new();
    if (config == NULL) return false;
    if (load_user_config) {
        ghostty_config_load_default_files(config);
        ghostty_config_load_recursive_files(config);
    }
    if (theme_config_path != NULL) {
        ghostty_config_load_file(config, theme_config_path);
    }
    ghostty_config_finalize(config);
    ghostty_surface_update_config(state->surface, config);
    ghostty_config_free(config);
    // Render the derived configuration now instead of waiting for the next
    // wakeup, so the new colors reach the layer as soon as possible.
    ghostty_surface_refresh(state->surface);
    return true;
}

bool gpui_ghostty_surface_snapshot(
    gpui_ghostty_surface *state,
    uint8_t **pixels,
    uint32_t *width,
    uint32_t *height,
    size_t *length
) {
    if (pixels == NULL || width == NULL || height == NULL || length == NULL) return false;
    *pixels = NULL;
    *width = 0;
    *height = 0;
    *length = 0;
    if (state == NULL || state->view == nil) return false;

    id contents = state->view.layer.contents;
    if (contents == nil || CFGetTypeID((CFTypeRef)contents) != IOSurfaceGetTypeID()) return false;
    IOSurfaceRef surface = (IOSurfaceRef)contents;
    CFRetain(surface);
    if (IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL) != kIOReturnSuccess) {
        CFRelease(surface);
        return false;
    }

    size_t surface_width = IOSurfaceGetWidth(surface);
    size_t surface_height = IOSurfaceGetHeight(surface);
    OSType pixel_format = IOSurfaceGetPixelFormat(surface);
    size_t source_stride = IOSurfaceGetBytesPerRow(surface);
    const uint8_t *source = IOSurfaceGetBaseAddress(surface);
    bool valid = pixel_format == kCVPixelFormatType_32BGRA && surface_width > 0 &&
        surface_height > 0 && source != NULL && surface_width <= UINT32_MAX &&
        surface_height <= UINT32_MAX &&
        surface_width <= SIZE_MAX / 4 && surface_height <= SIZE_MAX / (surface_width * 4) &&
        source_stride >= surface_width * 4;
    size_t destination_stride = valid ? surface_width * 4 : 0;
    size_t byte_length = valid ? destination_stride * surface_height : 0;
    uint8_t *copy = valid ? malloc(byte_length) : NULL;
    if (copy != NULL) {
        for (size_t row = 0; row < surface_height; row++) {
            memcpy(copy + row * destination_stride, source + row * source_stride, destination_stride);
        }
        *pixels = copy;
        *width = (uint32_t)surface_width;
        *height = (uint32_t)surface_height;
        *length = byte_length;
    }

    IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
    CFRelease(surface);
    return copy != NULL;
}

void gpui_ghostty_surface_snapshot_free(uint8_t *pixels) {
    free(pixels);
}

static void gpui_ghostty_apply_frame(
    gpui_ghostty_surface *state,
    double x,
    double y,
    double width,
    double height
) {
    double parent_height = NSHeight(state->parent.bounds);
    [state->view setFrame:NSMakeRect(x, parent_height - y - height, width, height)];
    double scale = state->parent.window.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor;
    ghostty_surface_set_content_scale(state->surface, scale, scale);
    ghostty_surface_set_size(state->surface, (uint32_t)(width * scale), (uint32_t)(height * scale));
    ghostty_surface_refresh(state->surface);
}

void gpui_ghostty_surface_set_frame(
    gpui_ghostty_surface *state,
    double x,
    double y,
    double width,
    double height
) {
    if (state == NULL || state->surface == NULL) return;
    state->view.layer.contentsGravity = kCAGravityTopLeft;
    gpui_ghostty_apply_frame(state, x, y, width, height);
}

void gpui_ghostty_surface_set_visible(gpui_ghostty_surface *state, bool visible) {
    if (state == NULL || state->surface == NULL) return;
    state->visible = visible;
    [state->view setHidden:!visible];
    if (!visible) gpui_ghostty_overlay_hide(gpui_ghostty_overlay_for(state->parent));
    ghostty_surface_set_occlusion(state->surface, visible || state->hidden_rendering);
    if (visible) ghostty_surface_refresh(state->surface);
}

// Keeps a hidden surface rendering so a caller that draws a captured frame can
// read the current one back. Cleared when the surface is visible again.
void gpui_ghostty_surface_set_hidden_rendering(
    gpui_ghostty_surface *state,
    bool rendered
) {
    if (state == NULL || state->surface == NULL) return;
    if (state->hidden_rendering == rendered) return;
    state->hidden_rendering = rendered;
    if (!state->visible) ghostty_surface_set_occlusion(state->surface, rendered);
}

void gpui_ghostty_surface_set_focus(gpui_ghostty_surface *state, bool focused) {
    if (state == NULL || state->surface == NULL) return;
    ghostty_app_set_focus(state->app, focused);
    ghostty_surface_set_focus(state->surface, focused);
}

bool gpui_ghostty_surface_key(
    gpui_ghostty_surface *state,
    int action,
    int modifiers,
    int consumed_modifiers,
    uint32_t keycode,
    const char *text,
    uint32_t unshifted_codepoint
) {
    if (state == NULL || state->surface == NULL) return false;
    ghostty_input_key_s event = {
        .action = (ghostty_input_action_e)action,
        .mods = (ghostty_input_mods_e)modifiers,
        .consumed_mods = (ghostty_input_mods_e)consumed_modifiers,
        .keycode = keycode,
        .text = text,
        .unshifted_codepoint = unshifted_codepoint,
        .composing = false,
    };
    return ghostty_surface_key(state->surface, event);
}

void gpui_ghostty_surface_text(gpui_ghostty_surface *state, const char *text, size_t length) {
    if (state != NULL && state->surface != NULL) ghostty_surface_text(state->surface, text, length);
}

void gpui_ghostty_surface_mouse_position(
    gpui_ghostty_surface *state,
    double x,
    double y,
    int modifiers
) {
    if (state != NULL && state->surface != NULL) {
        ghostty_surface_mouse_pos(state->surface, x, y, (ghostty_input_mods_e)modifiers);
    }
}

void gpui_ghostty_surface_mouse_button(
    gpui_ghostty_surface *state,
    int mouse_state,
    int button,
    int modifiers
) {
    if (state != NULL && state->surface != NULL) {
        ghostty_surface_mouse_button(
            state->surface,
            (ghostty_input_mouse_state_e)mouse_state,
            (ghostty_input_mouse_button_e)button,
            (ghostty_input_mods_e)modifiers
        );
    }
}

void gpui_ghostty_surface_mouse_scroll(
    gpui_ghostty_surface *state,
    double x,
    double y,
    int modifiers
) {
    if (state != NULL && state->surface != NULL) {
        ghostty_surface_mouse_scroll(state->surface, x, y, modifiers);
    }
}

void *gpui_ghostty_surface_take_clipboard_read(gpui_ghostty_surface *state, bool *selection) {
    if (state == NULL || state->clipboard_request == NULL) return NULL;
    void *request = state->clipboard_request;
    state->clipboard_request = NULL;
    if (selection != NULL) {
        *selection = state->clipboard_location == GHOSTTY_CLIPBOARD_SELECTION;
    }
    return request;
}

void gpui_ghostty_surface_complete_clipboard_read(
    gpui_ghostty_surface *state,
    void *request,
    const char *text
) {
    if (state != NULL && state->surface != NULL && request != NULL && text != NULL) {
        ghostty_surface_complete_clipboard_request(state->surface, text, request, false);
    }
}
