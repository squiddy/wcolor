#include <math.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <wayland-client.h>
#include <cairo/cairo.h>

#include "wlr-layer-shell-unstable-protocol.h"
#include "wlr-screencopy-unstable-protocol.h"
#include "xdg-shell-protocol.h"
#include "shm.h"

struct wcolor_seat
{
    struct wcolor_state *state;
    struct wl_pointer *pointer;
};

struct wcolor_surface
{
    struct wcolor_state *state;
    struct wl_output *output;
    struct wl_surface *surface;
    struct wl_surface *preview_surface;
    struct wl_subsurface *subsurface;
    struct zwlr_layer_surface_v1 *layer_surface;
    struct wl_shm_pool *pool;
    struct wl_buffer *background_buffer;
    struct wl_buffer *preview_buffer;
    struct zwlr_screencopy_frame_v1 *frame;
    uint32_t frame_flags;

    void *data;
    uint32_t width;
    uint32_t height;
    struct wl_list link;
};

struct wcolor_state
{
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_compositor *compositor;
    struct wl_subcompositor *subcompositor;
    struct wl_shm *shm;
    struct zwlr_layer_shell_v1 *layer_shell;
    struct zwlr_screencopy_manager_v1 *screencopy;
    struct wl_list surfaces;

    uint32_t color;
    int cursor_x;
    int cursor_y;
    bool running;
};

static void noop()
{
}

void create_pool(struct wcolor_surface *surface)
{
    int size = surface->width * 4 * surface->height + 300 * 4 * 300;
    int fd = allocate_shm_file(size);
    surface->data = mmap(NULL, size,
                         PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    surface->pool = wl_shm_create_pool(surface->state->shm, fd, size);
    close(fd);
}

void render(struct wcolor_surface *surface)
{
    struct wcolor_state *state = surface->state;

    wl_subsurface_set_position(surface->subsurface,
                               state->cursor_x - 50,
                               state->cursor_y - 50);
    wl_surface_attach(surface->preview_surface, NULL, 0, 0);
    wl_surface_commit(surface->preview_surface);

    int offset = surface->width * 4 * surface->height;
    if (surface->preview_buffer == NULL)
    {

        surface->preview_buffer = wl_shm_pool_create_buffer(surface->pool, offset,
                                                            100, 100, 100 * 4, WL_SHM_FORMAT_ARGB8888);
    }

    cairo_surface_t *cairo_surface = cairo_image_surface_create_for_data(surface->data + offset, CAIRO_FORMAT_ARGB32,
                                                                         100, 100, 100 * 4);

    uint32_t color;
    if (surface->frame_flags & ZWLR_SCREENCOPY_FRAME_V1_FLAGS_Y_INVERT)
    {
        void *pixel = surface->data + ((surface->height - state->cursor_y) * surface->width * 4 + state->cursor_x * 4);
        color = *(uint32_t *)pixel;
    }
    else
    {
        void *pixel = surface->data + (state->cursor_y * surface->width * 4 + state->cursor_x * 4);
        color = *(uint32_t *)pixel;
    }

    state->color = color;

    cairo_t *cairo = cairo_create(cairo_surface);
    memset(surface->data + offset, 0, 100 * 100 * 4);
    cairo_set_operator(cairo, CAIRO_OPERATOR_SOURCE);

    // Black outline
    cairo_set_source_rgb(cairo,
                         0.0,
                         0.0,
                         0.0);
    cairo_set_line_width(cairo, 22);
    cairo_arc(cairo, 50, 50, 30, 0, 2 * M_PI);
    cairo_stroke_preserve(cairo);

    // Circle filled with current color
    cairo_set_source_rgb(cairo,
                         (color >> (2 * 8) & 0xFF) / 255.0,
                         (color >> (1 * 8) & 0xFF) / 255.0,
                         (color >> (0 * 8) & 0xFF) / 255.0);
    cairo_set_line_width(cairo, 20);
    cairo_arc(cairo, 50, 50, 30, 0, 2 * M_PI);
    cairo_stroke_preserve(cairo);

    wl_surface_set_buffer_scale(surface->preview_surface, 1);
    wl_surface_attach(surface->preview_surface, surface->preview_buffer, 0, 0);
    wl_surface_damage(surface->preview_surface, 0, 0, UINT32_MAX, UINT32_MAX);
    wl_surface_commit(surface->preview_surface);

    wl_surface_commit(surface->surface);
}

static void screencopy_frame_handle_buffer(void *data,
                                           struct zwlr_screencopy_frame_v1 *frame, uint32_t format, uint32_t width,
                                           uint32_t height, uint32_t stride)
{
    struct wcolor_surface *surface = data;

    surface->background_buffer = wl_shm_pool_create_buffer(surface->pool, 0,
                                                           width, height, stride,
                                                           format);
    zwlr_screencopy_frame_v1_copy(frame, surface->background_buffer);
}

static void screencopy_frame_handle_flags(void *data,
                                          struct zwlr_screencopy_frame_v1 *frame, uint32_t flags)
{
    struct wcolor_surface *surface = data;
    surface->frame_flags = flags;
}

static void screencopy_frame_handle_ready(void *data,
                                          struct zwlr_screencopy_frame_v1 *frame, uint32_t tv_sec_hi,
                                          uint32_t tv_sec_lo, uint32_t tv_nsec)
{
    struct wcolor_surface *surface = data;

    if (surface->frame_flags & ZWLR_SCREENCOPY_FRAME_V1_FLAGS_Y_INVERT)
    {
        wl_surface_set_buffer_transform(surface->surface, WL_OUTPUT_TRANSFORM_FLIPPED_180);
    }
    wl_surface_set_buffer_scale(surface->surface, 1);
    wl_surface_attach(surface->surface, surface->background_buffer, 0, 0);
    wl_surface_damage(surface->surface, 0, 0, UINT32_MAX, UINT32_MAX);
    wl_surface_commit(surface->surface);
}

static void screencopy_frame_handle_failed(void *data,
                                           struct zwlr_screencopy_frame_v1 *frame)
{
}

static const struct zwlr_screencopy_frame_v1_listener screencopy_frame_listener = {
    .buffer = screencopy_frame_handle_buffer,
    .flags = screencopy_frame_handle_flags,
    .ready = screencopy_frame_handle_ready,
    .failed = screencopy_frame_handle_failed,
};

static void layer_surface_configure(void *data,
                                    struct zwlr_layer_surface_v1 *layer_surface,
                                    uint32_t serial, uint32_t width, uint32_t height)
{
    struct wcolor_surface *surface = data;
    surface->width = width;
    surface->height = height;
    zwlr_layer_surface_v1_ack_configure(layer_surface, serial);

    create_pool(surface);

    surface->frame = zwlr_screencopy_manager_v1_capture_output(
        surface->state->screencopy, 0, surface->output);
    zwlr_screencopy_frame_v1_add_listener(surface->frame,
                                          &screencopy_frame_listener, surface);
}

static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
    .configure = layer_surface_configure,
    .closed = noop,
};

static void create_layer_surface(struct wcolor_surface *surface)
{
    struct wcolor_state *state = surface->state;

    surface->surface = wl_compositor_create_surface(state->compositor);

    surface->preview_surface = wl_compositor_create_surface(state->compositor);

    // Assign empty region to pass through pointer events from subsurface to
    // main surface. Otherwise we would get relative pointer movements on our
    // preview surface.
    struct wl_region *region = wl_compositor_create_region(state->compositor);
    wl_region_add(region, 0, 0, 0, 0);
    wl_surface_set_input_region(surface->preview_surface, region);

    surface->subsurface = wl_subcompositor_get_subsurface(state->subcompositor, surface->preview_surface, surface->surface);
    wl_subsurface_set_desync(surface->subsurface);

    surface->layer_surface = zwlr_layer_shell_v1_get_layer_surface(
        state->layer_shell, surface->surface, surface->output,
        ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "overlay");

    zwlr_layer_surface_v1_set_size(surface->layer_surface, 0, 0);
    zwlr_layer_surface_v1_set_anchor(surface->layer_surface,
                                     ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
                                         ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT |
                                         ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
                                         ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT);
    zwlr_layer_surface_v1_set_exclusive_zone(surface->layer_surface, -1);
    zwlr_layer_surface_v1_add_listener(surface->layer_surface,
                                       &layer_surface_listener, surface);
    wl_surface_commit(surface->surface);
}

static void pointer_handle_motion(void *data, struct wl_pointer *pointer,
                                  uint32_t time, wl_fixed_t surface_x, wl_fixed_t surface_y)
{
    struct wcolor_seat *seat = data;
    struct wcolor_state *state = seat->state;

    state->cursor_x = wl_fixed_to_int(surface_x);
    state->cursor_y = wl_fixed_to_int(surface_y);

    struct wcolor_surface *surface;
    wl_list_for_each(surface, &state->surfaces, link)
    {
        render(surface);
    }
}

static void pointer_handle_button(void *data, struct wl_pointer *wl_pointer,
                                  uint32_t serial, uint32_t time, uint32_t button,
                                  uint32_t button_state)
{
    struct wcolor_seat *seat = data;
    struct wcolor_state *state = seat->state;

    if (button_state == WL_POINTER_BUTTON_STATE_PRESSED)
    {
        state->running = false;
    }
}

static void pointer_handle_enter(void *data, struct wl_pointer *wl_pointer,
                                 uint32_t serial, struct wl_surface *surface,
                                 wl_fixed_t surface_x, wl_fixed_t surface_y)
{
    wl_pointer_set_cursor(wl_pointer, serial, NULL, 0, 0);
}

static const struct wl_pointer_listener pointer_listener = {
    .enter = pointer_handle_enter,
    .leave = noop,
    .motion = pointer_handle_motion,
    .button = pointer_handle_button,
    .axis = noop,
};

static void seat_handle_capabilities(void *data, struct wl_seat *wl_seat,
                                     enum wl_seat_capability caps)
{
    struct wcolor_seat *seat = data;
    if (seat->pointer)
    {
        wl_pointer_release(seat->pointer);
        seat->pointer = NULL;
    }
    if ((caps & WL_SEAT_CAPABILITY_POINTER))
    {
        seat->pointer = wl_seat_get_pointer(wl_seat);
        wl_pointer_add_listener(seat->pointer, &pointer_listener, seat);
    }
}

const struct wl_seat_listener seat_listener = {
    .capabilities = seat_handle_capabilities,
    .name = noop,
};

static void
registry_global(void *data, struct wl_registry *registry,
                uint32_t name, const char *interface, uint32_t version)
{
    struct wcolor_state *state = data;

    if (strcmp(interface, wl_compositor_interface.name) == 0)
    {
        state->compositor = wl_registry_bind(registry, name,
                                             &wl_compositor_interface, 4);
    }
    else if (strcmp(interface, wl_subcompositor_interface.name) == 0)
    {
        state->subcompositor = wl_registry_bind(registry, name,
                                                &wl_subcompositor_interface, 1);
    }
    else if (strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0)
    {
        state->layer_shell = wl_registry_bind(registry, name,
                                              &zwlr_layer_shell_v1_interface, 2);
    }
    else if (strcmp(interface, wl_shm_interface.name) == 0)
    {
        state->shm = wl_registry_bind(registry, name,
                                      &wl_shm_interface, 1);
    }
    else if (strcmp(interface, wl_seat_interface.name) == 0)
    {
        struct wl_seat *wl_seat = wl_registry_bind(registry, name,
                                                   &wl_seat_interface, 1);
        struct wcolor_seat *seat = calloc(1, sizeof(struct wcolor_seat));
        seat->state = state;

        wl_seat_add_listener(wl_seat, &seat_listener, seat);
    }
    else if (strcmp(interface, wl_output_interface.name) == 0)
    {
        struct wl_output *output = wl_registry_bind(registry, name,
                                                    &wl_output_interface, 3);
        struct wcolor_surface *surface = calloc(1, sizeof(struct wcolor_surface));
        surface->state = state;
        surface->output = output;
        wl_list_insert(&state->surfaces, &surface->link);
    }
    else if (strcmp(interface, zwlr_screencopy_manager_v1_interface.name) == 0)
    {
        state->screencopy = wl_registry_bind(registry, name,
                                             &zwlr_screencopy_manager_v1_interface, 1);
    }
}

const static struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = noop,
};

int main(int argc, char *argv[])
{
    struct wcolor_state state = {.running = 1};
    wl_list_init(&state.surfaces);

    state.display = wl_display_connect(NULL);
    state.registry = wl_display_get_registry(state.display);
    wl_registry_add_listener(state.registry, &registry_listener, &state);
    wl_display_roundtrip(state.display);

    struct wcolor_surface *surface;
    wl_list_for_each(surface, &state.surfaces, link)
    {
        create_layer_surface(surface);
    }
    wl_display_roundtrip(state.display);

    while (state.running && wl_display_dispatch(state.display) != -1)
    {
    }

    printf("#%X\n", state.color & 0xFFFFFF);

    return 0;
}