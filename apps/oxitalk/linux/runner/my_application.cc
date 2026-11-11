#include "my_application.h"

#include <cstring>

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // io.oxisoft.oxitalk/clipboard: writes images, which the pasteboard plugin can't on Linux.
  FlMethodChannel* clipboard_channel;
  // io.oxisoft.oxitalk/links: the matrix.to or matrix: link of a second launch, which
  // GApplication hands to this (the first) instance; takeLink gives it to Dart.
  FlMethodChannel* links_channel;
  gchar* pending_link;
  // The window, once activated; cleared when it goes.
  GtkWindow* window;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// writeImage(Uint8List png): puts the image on the clipboard; GTK serves it in every
// image format another app asks for while OxiTalk runs.
static void clipboard_method_cb(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  if (g_strcmp0(fl_method_call_get_name(method_call), "writeImage") != 0) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(method_call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_UINT8_LIST) {
    fl_method_call_respond_error(method_call, "args", "expected image bytes",
                                 nullptr, nullptr);
    return;
  }
  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkPixbufLoader) loader = gdk_pixbuf_loader_new();
  gboolean ok = gdk_pixbuf_loader_write(loader, fl_value_get_uint8_list(args),
                                        fl_value_get_length(args), &error) &&
                gdk_pixbuf_loader_close(loader, &error);
  GdkPixbuf* pixbuf = ok ? gdk_pixbuf_loader_get_pixbuf(loader) : nullptr;
  if (pixbuf == nullptr) {
    fl_method_call_respond_error(
        method_call, "decode", error != nullptr ? error->message : "not an image",
        nullptr, nullptr);
    return;
  }
  gtk_clipboard_set_image(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD), pixbuf);
  gtk_clipboard_store(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD));
  fl_method_call_respond_success(method_call, nullptr, nullptr);
}

// Whether |arg| is a link OxiTalk opens (see lib/src/app/matrix_link.dart isMatrixLink).
static gboolean is_matrix_link(const gchar* arg) {
  if (arg == nullptr) return FALSE;
  if (g_ascii_strncasecmp(arg, "matrix:", 7) == 0) return TRUE;
  const gchar* prefixes[] = {"https://matrix.to/", "http://matrix.to/",
                             "https://www.matrix.to/", "http://www.matrix.to/"};
  for (const gchar* prefix : prefixes) {
    if (g_ascii_strncasecmp(arg, prefix, strlen(prefix)) == 0) return TRUE;
  }
  return FALSE;
}

// takeLink: the link of the last second launch, once; null for none.
static void links_method_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                            gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (g_strcmp0(fl_method_call_get_name(method_call), "takeLink") != 0) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }
  g_autoptr(FlValue) result = self->pending_link != nullptr
                                  ? fl_value_new_string(self->pending_link)
                                  : fl_value_new_null();
  g_clear_pointer(&self->pending_link, g_free);
  fl_method_call_respond_success(method_call, result, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  // One window, one engine, one Matrix store: activated again, it comes to the front.
  if (self->window != nullptr) {
    gtk_window_present(self->window);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  g_object_add_weak_pointer(G_OBJECT(window),
                            reinterpret_cast<gpointer*>(&self->window));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "OxiTalk");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "OxiTalk");
  }

  gtk_window_set_default_size(window, 1280, 720);

  // Window icon from the bundle's data dir (next to the executable).
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe != nullptr) {
    g_autofree gchar* dir = g_path_get_dirname(exe);
    g_autofree gchar* icon =
        g_build_filename(dir, "data", "app_icon.png", nullptr);
    gtk_window_set_icon_from_file(window, icon, nullptr);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->clipboard_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "io.oxisoft.oxitalk/clipboard", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->clipboard_channel, clipboard_method_cb, nullptr, nullptr);
  self->links_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "io.oxisoft.oxitalk/links", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->links_channel,
                                            links_method_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::command_line, in the first instance: for its own launch, whose
// arguments (files and links named on the command line) go to Dart's main, and for every
// later launch (a clicked matrix: link runs `oxitalk %U` again), whose link goes to the
// running app over the links channel instead of starting a second app.
static gint my_application_command_line(GApplication* application,
                                        GApplicationCommandLine* command_line) {
  MyApplication* self = MY_APPLICATION(application);
  gint argc = 0;
  g_auto(GStrv) argv =
      g_application_command_line_get_arguments(command_line, &argc);
  if (self->window == nullptr) {
    // Strip out the first argument as it is the binary name.
    g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
    self->dart_entrypoint_arguments =
        g_strdupv(argc > 0 ? argv + 1 : argv);
    g_application_activate(application);
    return 0;
  }
  for (gint i = 1; i < argc; i++) {
    if (!is_matrix_link(argv[i])) continue;
    g_free(self->pending_link);
    self->pending_link = g_strdup(argv[i]);
    if (self->links_channel != nullptr) {
      fl_method_channel_invoke_method(self->links_channel, "linkArrived",
                                      nullptr, nullptr, nullptr, nullptr);
    }
    break;
  }
  gtk_window_present(self->window);
  return 0;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->clipboard_channel);
  g_clear_object(&self->links_channel);
  g_clear_pointer(&self->pending_link, g_free);
  if (self->window != nullptr) {
    g_object_remove_weak_pointer(G_OBJECT(self->window),
                                 reinterpret_cast<gpointer*>(&self->window));
    self->window = nullptr;
  }
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // Unique: a second launch hands its command line to the running instance
  // (my_application_command_line) and exits.
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_COMMAND_LINE,
                                     nullptr));
}
