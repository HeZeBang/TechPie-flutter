#ifndef RUNNER_UNI_AUTH_WINDOW_H_
#define RUNNER_UNI_AUTH_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <webkit2/webkit2.h>

// A GTK authentication window with no secondary Flutter engine.
class UniAuthWindow {
 public:
  UniAuthWindow(FlBinaryMessenger* messenger, GtkWindow* parent);
  ~UniAuthWindow();

 private:
  void Authenticate(FlMethodCall* call);
  void Complete(const gchar* callback);
  GtkWindow* parent_;
  GtkWidget* window_ = nullptr;
  GtkWidget* status_ = nullptr;
  WebKitWebView* webview_ = nullptr;
  FlMethodChannel* channel_;
  FlMethodCall* pending_ = nullptr;
};

#endif  // RUNNER_UNI_AUTH_WINDOW_H_
