#include "my_application.h"
#include "deadline_snapshot_store.h"
#include "uni_auth_window.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* deadline_channel;
  gboolean pending_deadlines;
  UniAuthWindow* uni_auth_window;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void deadline_call(FlMethodChannel* channel, FlMethodCall* call, gpointer data) {
  MyApplication* self = MY_APPLICATION(data);
  const gchar* method = fl_method_call_get_name(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_str_equal(method, "consumePendingRoute")) {
    g_autoptr(FlValue) value = fl_value_new_bool(self->pending_deadlines);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (g_str_equal(method, "acknowledgePendingRoute")) {
    self->pending_deadlines = FALSE;
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_str_equal(method, "publish") || g_str_equal(method, "clear")) {
    g_autoptr(GError) error = nullptr;
    FlValue* args = fl_method_call_get_args(call);
    gboolean ok;
    if (g_str_equal(method, "clear")) ok = deadline_snapshot_clear(&error);
    else ok = deadline_snapshot_write(
        args && fl_value_get_type(args) == FL_VALUE_TYPE_STRING ? fl_value_get_string(args) : nullptr,
        &error);
    response = ok ? FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr))
                  : FL_METHOD_RESPONSE(fl_method_error_response_new("DEADLINE_WIDGET_STORAGE_UNAVAILABLE",
                        error ? error->message : "Invalid snapshot", nullptr));
  } else response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(call, response, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* existing = gtk_application_get_active_window(GTK_APPLICATION(application));
  if (existing) {
    gtk_window_present(existing);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

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
    gtk_header_bar_set_title(header_bar, "TechPie");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "TechPie");
  }

  gtk_window_set_default_size(window, 1280, 720);

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
  delete self->uni_auth_window;
  self->uni_auth_window = new UniAuthWindow(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), window);
  g_clear_object(&self->deadline_channel);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->deadline_channel = fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "techpie/deadline_widgets", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->deadline_channel, deadline_call, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  for (guint i = 1; (*arguments)[i]; i++) {
    if (deadline_uri_valid((*arguments)[i])) {
      g_autoptr(GFile) file = g_file_new_for_uri((*arguments)[i]);
      GFile* files[] = {file};
      g_application_open(application, files, 1, "");
      *exit_status = 0;
      return TRUE;
    }
  }
  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_open(GApplication* application, GFile** files, gint count,
                                const gchar*) {
  MyApplication* self = MY_APPLICATION(application);
  gboolean accepted = FALSE;
  for (gint i = 0; i < count; i++) {
    g_autofree gchar* uri = g_file_get_uri(files[i]);
    if (deadline_uri_valid(uri)) accepted = TRUE;
  }
  if (!accepted) return;
  const gboolean running = self->deadline_channel &&
      gtk_application_get_active_window(GTK_APPLICATION(application));
  self->pending_deadlines = TRUE;
  g_application_activate(application);
  if (running)
    fl_method_channel_invoke_method(self->deadline_channel, "openDeadlines", nullptr,
                                  nullptr, nullptr, nullptr);
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
  delete self->uni_auth_window;
  self->uni_auth_window = nullptr;
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->deadline_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
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

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_OPEN, nullptr));
}
