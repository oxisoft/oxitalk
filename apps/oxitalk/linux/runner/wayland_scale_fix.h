#ifndef RUNNER_WAYLAND_SCALE_FIX_H_
#define RUNNER_WAYLAND_SCALE_FIX_H_

// Works around flutter/flutter#196476 (Flutter 3.50, Wayland): the view's
// subsurface keeps the buffer scale it was created with. See the .cc file.

// Installs the EGL hooks. Call on Wayland only, before the Flutter view is
// created, with the window's current scale.
void wayland_scale_fix_install(int scale);

// The window's scale changed; the next suitable frame carries it.
void wayland_scale_fix_set_scale(int scale);

#endif  // RUNNER_WAYLAND_SCALE_FIX_H_
