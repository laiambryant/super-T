.pragma library

function fromShell(text, pluginId) {
  try {
    var config = JSON.parse(String(text));
    if (!config || typeof config !== "object" || Array.isArray(config))
      return { ok: false, error: "shell.json must contain an object" };
    if (config.plugins !== undefined && !Array.isArray(config.plugins))
      return { ok: false, error: "shell.json plugins must be an array" };
    var entries = config.plugins || [];
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] && entries[i].id === pluginId)
        return { ok: true, value: entries[i].dir };
    }
    return { ok: true, value: undefined };
  } catch (error) {
    return { ok: false, error: "Could not parse shell.json: " + error.message };
  }
}

function resolve(value, home) {
  if (value === undefined) value = home + "/Documents/todos";
  if (typeof value !== "string")
    return { ok: false, path: "", error: "Todo dir must be a path string" };
  if (/[\x00-\x1f\x7f]/.test(value))
    return { ok: false, path: "", error: "Todo dir cannot contain control characters" };
  var path = value.trim();
  if (!path) return { ok: false, path: "", error: "Todo dir cannot be empty" };
  if (path === "~" || path.indexOf("~/") === 0) path = home + path.slice(1);
  if (path.charAt(0) !== "/")
    return { ok: false, path: "", error: "Todo dir must be absolute or start with ~/" };
  path = path.replace(/\/+$/, "") || "/";
  return { ok: true, path: path, error: "" };
}
