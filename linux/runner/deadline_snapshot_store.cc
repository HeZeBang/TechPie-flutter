#include "deadline_snapshot_store.h"

#include <json-glib/json-glib.h>
#include <glib/gstdio.h>
#include <cmath>
#include <cstring>

static gboolean number(JsonObject* object, const char* key) {
  if (!json_object_has_member(object, key)) return FALSE;
  JsonNode* node = json_object_get_member(object, key);
  if (!JSON_NODE_HOLDS_VALUE(node)) return FALSE;
  const GType type = json_node_get_value_type(node);
  if (type != G_TYPE_INT64 && type != G_TYPE_DOUBLE) return FALSE;
  const double value = json_node_get_double(node);
  return std::isfinite(value) && value >= 0 && value <= 253402300799.0;
}

static const gchar* string(JsonObject* object, const char* key, gsize limit) {
  if (!json_object_has_member(object, key)) return nullptr;
  JsonNode* node = json_object_get_member(object, key);
  if (!JSON_NODE_HOLDS_VALUE(node) || json_node_get_value_type(node) != G_TYPE_STRING)
    return nullptr;
  const gchar* value = json_node_get_string(node);
  return value && std::strlen(value) <= limit ? value : nullptr;
}

gchar* deadline_snapshot_path() {
  return g_build_filename(g_get_user_data_dir(), "techpie", "widgets",
                          "deadline-widget-v1.json", nullptr);
}

gboolean deadline_snapshot_valid(const gchar* json, gsize length) {
  if (!json || length > 262144 || std::strlen(json) != length) return FALSE;
  g_autoptr(JsonParser) parser = json_parser_new();
  if (!json_parser_load_from_data(parser, json, length, nullptr)) return FALSE;
  JsonNode* root = json_parser_get_root(parser);
  if (!root || !JSON_NODE_HOLDS_OBJECT(root)) return FALSE;
  JsonObject* object = json_node_get_object(root);
  if (json_object_get_size(object) != 3 || !number(object, "schemaVersion") ||
      json_object_get_double_member(object, "schemaVersion") != 1 ||
      !number(object, "writtenAt") || !json_object_has_member(object, "items"))
    return FALSE;
  JsonNode* items_node = json_object_get_member(object, "items");
  if (!JSON_NODE_HOLDS_ARRAY(items_node)) return FALSE;
  JsonArray* items = json_node_get_array(items_node);
  if (json_array_get_length(items) > 512) return FALSE;
  g_autoptr(GHashTable) ids = g_hash_table_new(g_str_hash, g_str_equal);
  for (guint i = 0; i < json_array_get_length(items); i++) {
    JsonNode* node = json_array_get_element(items, i);
    if (!JSON_NODE_HOLDS_OBJECT(node)) return FALSE;
    JsonObject* item = json_node_get_object(node);
    const gchar* id = string(item, "id", 4096);
    const gchar* kind = string(item, "kind", 16);
    if (json_object_get_size(item) != 5 || !id || !*id || !kind ||
        (g_strcmp0(kind, "exam") && g_strcmp0(kind, "assignment")) ||
        !string(item, "title", 4096) || !string(item, "course", 4096) ||
        !number(item, "dueAt") || g_hash_table_contains(ids, id)) return FALSE;
    g_hash_table_add(ids, const_cast<gchar*>(id));
  }
  return TRUE;
}

gboolean deadline_snapshot_write(const gchar* json, GError** error) {
  if (!deadline_snapshot_valid(json, json ? std::strlen(json) : 0)) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_DATA, "Invalid deadline snapshot");
    return FALSE;
  }
  g_autofree gchar* path = deadline_snapshot_path();
  g_autofree gchar* directory = g_path_get_dirname(path);
  if (g_mkdir_with_parents(directory, 0700) != 0 || g_chmod(directory, 0700) != 0) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED, "Cannot create widget directory");
    return FALSE;
  }
  return g_file_set_contents_full(path, json, -1,
      static_cast<GFileSetContentsFlags>(G_FILE_SET_CONTENTS_CONSISTENT | G_FILE_SET_CONTENTS_DURABLE),
      0600, error);
}

gboolean deadline_snapshot_clear(GError** error) {
  g_autofree gchar* path = deadline_snapshot_path();
  g_autoptr(GFile) file = g_file_new_for_path(path);
  g_autoptr(GError) local = nullptr;
  if (g_file_delete(file, nullptr, &local) ||
      g_error_matches(local, G_IO_ERROR, G_IO_ERROR_NOT_FOUND)) return TRUE;
  g_propagate_error(error, g_steal_pointer(&local));
  return FALSE;
}

gboolean deadline_uri_valid(const gchar* uri) {
  return g_strcmp0(uri, "techpie://deadlines") == 0 ||
         g_strcmp0(uri, "techpie://deadlines/") == 0;
}
