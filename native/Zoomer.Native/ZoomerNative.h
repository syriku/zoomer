#ifndef ZOOMER_NATIVE_H
#define ZOOMER_NATIVE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t display_id;
    double x;
    double y;
    double width;
    double height;
    double backing_scale;
} zmr_display_descriptor;

typedef void (*zmr_simple_callback)(void *context);
typedef void (*zmr_capture_callback)(void *context, int64_t request_id,
                                     void *image, zmr_display_descriptor display,
                                     int32_t error_code, const char *error_message);
typedef void (*zmr_zoom_callback)(void *context, double delta_y, double x, double y);
typedef void (*zmr_magnify_callback)(void *context, double magnification, double x, double y);
typedef void (*zmr_pan_callback)(void *context, double delta_x, double delta_y);

typedef struct {
    zmr_simple_callback present_requested;
    zmr_simple_callback permission_requested;
    zmr_simple_callback quit_requested;
    zmr_simple_callback hotkey_triggered;
} zmr_app_callbacks;

typedef struct {
    zmr_simple_callback dismiss_requested;
    zmr_zoom_callback zoom_requested;
    zmr_magnify_callback magnify_requested;
    zmr_pan_callback pan_requested;
    zmr_simple_callback reset_requested;
    zmr_simple_callback display_disconnected;
} zmr_window_callbacks;

int32_t zmr_app_initialize(void *context, zmr_app_callbacks callbacks);
int32_t zmr_app_run(void);
void zmr_app_stop(void);
void zmr_app_set_menu(bool can_present, const char *status_text, bool authorized);

bool zmr_hotkey_register(void);
void zmr_hotkey_unregister(void);

bool zmr_permission_is_authorized(void);
bool zmr_permission_request(void);
void zmr_permission_open_settings(void);

void zmr_capture_display(int64_t request_id, void *context, zmr_capture_callback callback);
void zmr_image_release(void *image);

void *zmr_window_create(void *context, zmr_window_callbacks callbacks,
                        void *image, zmr_display_descriptor display);
void zmr_window_show(void *window);
void zmr_window_update_transform(void *window, double scale, double offset_x,
                                 double offset_y, bool show_hud);
void zmr_window_destroy(void *window);

#ifdef __cplusplus
}
#endif
#endif
