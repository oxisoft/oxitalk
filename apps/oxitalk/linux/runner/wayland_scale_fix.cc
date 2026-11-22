// Keeps the Flutter view's Wayland subsurface at the window's current scale.
//
// Flutter 3.50's Wayland renderer (FlViewRendererSubsurface) draws into a
// subsurface whose buffer scale it sets once, when the subsurface is created,
// and never again. Move the window to a monitor with another scale (or change
// the monitor's scale) and the engine renders at the new scale into a surface
// still declared at the old one: the content is drawn at the wrong size in the
// top left corner, the rest of the window black, clicks off target.
// flutter/flutter#196476; 3.47 did not have this renderer.
//
// The engine reaches EGL through libepoxy, whose entry points are writable
// function pointers. Wrapping eglCreateWindowSurface tells us the subsurface's
// wl_egl_window (and so its wl_surface); wrapping eglSwapBuffers lets the new
// buffer scale go out with a commit whose buffer size is a whole multiple of
// it, which the compositor requires (mutter ends the client otherwise).
//
// Remove once the engine updates the buffer scale itself.

#include "wayland_scale_fix.h"

#include <dlfcn.h>

#include <atomic>
#include <cstdint>
#include <map>
#include <mutex>

namespace {

// <wayland-egl-backend.h>, WL_EGL_WINDOW_VERSION 3. A stable ABI: Mesa reads
// the same fields.
struct WlEglWindow {
  const intptr_t version;
  int width;
  int height;
  int dx;
  int dy;
  int attached_width;
  int attached_height;
  void* driver_private;
  void (*resize_callback)(WlEglWindow*, void*);
  void (*destroy_window_callback)(void*);
  void* surface;  // struct wl_surface*
};

using CreateWindowSurface = void* (*)(void*, void*, void*, const int32_t*);
using SwapBuffers = unsigned (*)(void*, void*);
using DestroySurface = unsigned (*)(void*, void*);
using ProxyMarshal = void (*)(void*, uint32_t, ...);

constexpr uint32_t kWlSurfaceSetBufferScale = 8;

struct Tracked {
  WlEglWindow* window;
  int applied_scale;
  int previous_width;
  int previous_height;
};

CreateWindowSurface real_create = nullptr;
SwapBuffers real_swap = nullptr;
DestroySurface real_destroy = nullptr;
ProxyMarshal proxy_marshal = nullptr;

std::atomic<int> wanted_scale{0};
std::mutex surfaces_mutex;
std::map<void*, Tracked>* surfaces = new std::map<void*, Tracked>();

bool divisible(int width, int height, int scale) {
  return width % scale == 0 && height % scale == 0;
}

void* create_window_surface(void* display,
                            void* config,
                            void* native_window,
                            const int32_t* attributes) {
  void* surface = real_create(display, config, native_window, attributes);
  if (surface != nullptr && native_window != nullptr) {
    auto* window = static_cast<WlEglWindow*>(native_window);
    std::lock_guard<std::mutex> lock(surfaces_mutex);
    // The engine sets the window's scale on the surface right after creating
    // it, and the window's scale is what wanted_scale holds.
    (*surfaces)[surface] = {window, wanted_scale.load(), window->width,
                            window->height};
  }
  return surface;
}

unsigned swap_buffers(void* display, void* surface) {
  const int scale = wanted_scale.load();
  {
    std::lock_guard<std::mutex> lock(surfaces_mutex);
    auto it = surfaces->find(surface);
    if (it != surfaces->end()) {
      Tracked& tracked = it->second;
      WlEglWindow* window = tracked.window;
      // The buffer this swap commits was sized either at the previous swap or
      // now, depending on the driver: both have to fit the new scale.
      if (scale > 0 && scale != tracked.applied_scale &&
          window->surface != nullptr &&
          divisible(window->width, window->height, scale) &&
          divisible(tracked.previous_width, tracked.previous_height, scale)) {
        proxy_marshal(window->surface, kWlSurfaceSetBufferScale, scale);
        tracked.applied_scale = scale;
      }
      tracked.previous_width = window->width;
      tracked.previous_height = window->height;
    }
  }
  return real_swap(display, surface);
}

unsigned destroy_surface(void* display, void* surface) {
  {
    std::lock_guard<std::mutex> lock(surfaces_mutex);
    surfaces->erase(surface);
  }
  return real_destroy(display, surface);
}

void* egl_symbol(void* egl, const char* name) {
  void* symbol = egl != nullptr ? dlsym(egl, name) : nullptr;
  return symbol != nullptr ? symbol : dlsym(RTLD_DEFAULT, name);
}

}  // namespace

void wayland_scale_fix_install(int scale) {
  wanted_scale.store(scale);
  if (real_swap != nullptr) return;

  void* egl = dlopen("libEGL.so.1", RTLD_NOW | RTLD_GLOBAL);
  auto create = reinterpret_cast<CreateWindowSurface>(
      egl_symbol(egl, "eglCreateWindowSurface"));
  auto swap = reinterpret_cast<SwapBuffers>(egl_symbol(egl, "eglSwapBuffers"));
  auto destroy =
      reinterpret_cast<DestroySurface>(egl_symbol(egl, "eglDestroySurface"));
  auto marshal =
      reinterpret_cast<ProxyMarshal>(dlsym(RTLD_DEFAULT, "wl_proxy_marshal"));

  // libepoxy's dispatch pointers (data symbols, see `nm -D libepoxy.so.0`).
  auto epoxy_create = static_cast<CreateWindowSurface*>(
      dlsym(RTLD_DEFAULT, "epoxy_eglCreateWindowSurface"));
  auto epoxy_swap =
      static_cast<SwapBuffers*>(dlsym(RTLD_DEFAULT, "epoxy_eglSwapBuffers"));
  auto epoxy_destroy = static_cast<DestroySurface*>(
      dlsym(RTLD_DEFAULT, "epoxy_eglDestroySurface"));

  if (create == nullptr || swap == nullptr || destroy == nullptr ||
      marshal == nullptr || epoxy_create == nullptr || epoxy_swap == nullptr ||
      epoxy_destroy == nullptr) {
    return;  // Nothing to hook: leave rendering exactly as the engine does it.
  }

  real_create = create;
  real_swap = swap;
  real_destroy = destroy;
  proxy_marshal = marshal;
  *epoxy_create = create_window_surface;
  *epoxy_swap = swap_buffers;
  *epoxy_destroy = destroy_surface;
}

void wayland_scale_fix_set_scale(int scale) {
  wanted_scale.store(scale);
}
