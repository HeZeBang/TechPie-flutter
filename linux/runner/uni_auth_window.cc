#include "uni_auth_window.h"

UniAuthWindow::UniAuthWindow(FlBinaryMessenger* messenger, GtkWindow* parent)
    : parent_(parent) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger, "techpie/uni_auth", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_,
      [](FlMethodChannel*, FlMethodCall* call, gpointer data) {
        auto* self = static_cast<UniAuthWindow*>(data);
        if (g_str_equal(fl_method_call_get_name(call), "authenticate")) {
          self->Authenticate(call);
        } else {
          g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
          fl_method_call_respond(call, response, nullptr);
        }
      }, this, nullptr);
}

UniAuthWindow::~UniAuthWindow() {
  if (window_) gtk_widget_destroy(window_);
  fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr, nullptr);
  g_clear_object(&channel_);
}

void UniAuthWindow::Complete(const gchar* callback) {
  if (!pending_) return;
  g_autoptr(FlMethodResponse) response = nullptr;
  if (callback) {
    g_autoptr(FlValue) value = fl_value_new_string(callback);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new("CANCELLED", "Login cancelled", nullptr));
  }
  fl_method_call_respond(pending_, response, nullptr);
  g_clear_object(&pending_);
}

void UniAuthWindow::Authenticate(FlMethodCall* call) {
  FlValue* args = fl_method_call_get_args(call);
  const gchar* url = nullptr;
  const gchar* proxy = nullptr;
  if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* url_value = fl_value_lookup_string(args, "url");
    FlValue* proxy_value = fl_value_lookup_string(args, "proxy");
    if (url_value && fl_value_get_type(url_value) == FL_VALUE_TYPE_STRING) url = fl_value_get_string(url_value);
    if (proxy_value && fl_value_get_type(proxy_value) == FL_VALUE_TYPE_STRING) proxy = fl_value_get_string(proxy_value);
  }
  g_autoptr(GUri) uri = url ? g_uri_parse(url, G_URI_FLAGS_NONE, nullptr) : nullptr;
  if (!uri || g_strcmp0(g_uri_get_scheme(uri), "https") ||
      g_strcmp0(g_uri_get_host(uri), "auth.geekpie.club")) {
    fl_method_call_respond_error(call, "INVALID_URL", "Invalid authorization URL", nullptr, nullptr);
    return;
  }
  if (pending_) {
    gtk_window_present(GTK_WINDOW(window_));
    fl_method_call_respond_error(call, "IN_PROGRESS", "Login already open", nullptr, nullptr);
    return;
  }
  pending_ = FL_METHOD_CALL(g_object_ref(call));
  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(window_), "GeekPie UniAuth");
  gtk_window_set_default_size(GTK_WINDOW(window_), 520, 720);
  gtk_window_set_transient_for(GTK_WINDOW(window_), parent_);
  gtk_window_set_destroy_with_parent(GTK_WINDOW(window_), TRUE);
  gtk_window_set_modal(GTK_WINDOW(window_), TRUE);
  g_signal_connect(window_, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer data) {
    auto* self = static_cast<UniAuthWindow*>(data);
    self->window_ = self->status_ = nullptr;
    self->webview_ = nullptr;
    self->Complete(nullptr);
  }), this);

  GtkWidget* box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_container_add(GTK_CONTAINER(window_), box);
  GtkWidget* header = gtk_header_bar_new();
  gtk_header_bar_set_title(GTK_HEADER_BAR(header), "GeekPie UniAuth");
  gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(header), TRUE);
  gtk_window_set_titlebar(GTK_WINDOW(window_), header);
  GtkWidget* retry = gtk_button_new_with_label("重新加载");
  gtk_header_bar_pack_start(GTK_HEADER_BAR(header), retry);
  g_signal_connect(retry, "clicked", G_CALLBACK(+[](GtkButton*, gpointer data) {
    auto* self = static_cast<UniAuthWindow*>(data);
    if (self->webview_) webkit_web_view_reload(self->webview_);
  }), this);
  status_ = gtk_label_new("正在加载登录页…");
  gtk_label_set_line_wrap(GTK_LABEL(status_), TRUE);
  gtk_box_pack_start(GTK_BOX(box), status_, FALSE, FALSE, 4);
  g_autoptr(WebKitWebContext) context = webkit_web_context_new_ephemeral();
  if (proxy && *proxy) {
    g_autoptr(WebKitNetworkProxySettings) settings = webkit_network_proxy_settings_new(nullptr, nullptr);
    webkit_network_proxy_settings_add_proxy_for_scheme(settings, "http", proxy);
    webkit_network_proxy_settings_add_proxy_for_scheme(settings, "https", proxy);
    webkit_website_data_manager_set_network_proxy_settings(
        webkit_web_context_get_website_data_manager(context), WEBKIT_NETWORK_PROXY_MODE_CUSTOM, settings);
  } else {
    webkit_website_data_manager_set_network_proxy_settings(
        webkit_web_context_get_website_data_manager(context), WEBKIT_NETWORK_PROXY_MODE_NO_PROXY, nullptr);
  }
  webview_ = WEBKIT_WEB_VIEW(webkit_web_view_new_with_context(context));
  // Avoid the WebKit/NVIDIA EGL rendering path in this small login window.
  webkit_settings_set_hardware_acceleration_policy(webkit_web_view_get_settings(webview_),
      WEBKIT_HARDWARE_ACCELERATION_POLICY_NEVER);
  gtk_box_pack_start(GTK_BOX(box), GTK_WIDGET(webview_), TRUE, TRUE, 0);
  g_signal_connect(webview_, "load-changed", G_CALLBACK(+[](WebKitWebView*, WebKitLoadEvent event, gpointer data) {
    auto* self = static_cast<UniAuthWindow*>(data);
    if (!self->status_) return;
    if (event == WEBKIT_LOAD_STARTED) {
      gtk_label_set_text(GTK_LABEL(self->status_), "正在加载登录页…");
      gtk_widget_show(self->status_);
    } else if (event == WEBKIT_LOAD_COMMITTED) {
      gtk_widget_hide(self->status_);
    }
  }), this);
  g_signal_connect(webview_, "load-failed", G_CALLBACK(+[](WebKitWebView*, WebKitLoadEvent,
      const gchar*, GError* error, gpointer data) -> gboolean {
    auto* self = static_cast<UniAuthWindow*>(data);
    if (!self->status_ || g_error_matches(error, WEBKIT_NETWORK_ERROR, WEBKIT_NETWORK_ERROR_CANCELLED)) return FALSE;
    gtk_label_set_text(GTK_LABEL(self->status_), "登录页加载失败，请检查网络后点击“重新加载”。");
    gtk_widget_show(self->status_);
    return TRUE;
  }), this);
  g_signal_connect(webview_, "decide-policy", G_CALLBACK(+[](WebKitWebView* view,
      WebKitPolicyDecision* decision, WebKitPolicyDecisionType type, gpointer data) -> gboolean {
    if (type != WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION &&
        type != WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) return FALSE;
    auto* self = static_cast<UniAuthWindow*>(data);
    auto* navigation = WEBKIT_NAVIGATION_POLICY_DECISION(decision);
    auto* action = webkit_navigation_policy_decision_get_navigation_action(navigation);
    const gchar* url = webkit_uri_request_get_uri(webkit_navigation_action_get_request(action));
    g_autoptr(GUri) uri = g_uri_parse(url, G_URI_FLAGS_NONE, nullptr);
    if (uri && g_strcmp0(g_uri_get_scheme(uri), "techpie") == 0) {
      webkit_policy_decision_ignore(decision);
      if (g_strcmp0(g_uri_get_host(uri), "auth-callback") == 0) {
        self->Complete(url);
        // GTK queues the close request instead of destroying inside WebKit.
        gtk_window_close(GTK_WINDOW(self->window_));
      }
      return TRUE;
    }
    if (type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
      webkit_policy_decision_ignore(decision);
      if (uri && (g_strcmp0(g_uri_get_scheme(uri), "https") == 0 ||
                  g_strcmp0(g_uri_get_scheme(uri), "http") == 0))
        webkit_web_view_load_uri(view, url);
      return TRUE;
    }
    return FALSE;
  }), this);
  gtk_widget_show_all(window_);
  webkit_web_view_load_uri(webview_, url);
}
