import re

# Modules whose source file path can't be auto-derived from the
# CamelCase → snake_case convention (e.g., live in a different
# directory, or are named after the umbrella supervisor).
MODULE_OVERRIDES = {
    "Logflare.LogEvent": "lib/logflare/logs/log_event.ex",
    "Logflare.LogEvent.TypeDetection": "lib/logflare/logs/log_event/type_detection.ex",
    "Logflare.Supervisor": "lib/logflare/application.ex",
}


def _module_to_path(name):
    if name in MODULE_OVERRIDES:
        return MODULE_OVERRIDES[name]
    parts = [re.sub(r"(?<!^)(?=[A-Z])", "_", p).lower() for p in name.split(".")]
    return "lib/" + "/".join(parts) + ".ex"


def define_env(env):
    repo = env.variables["code_repo"]
    branch = env.variables["code_branch"]

    def _blob_url(path, line=None):
        is_dir = path.endswith("/")
        kind = "tree" if is_dir else "blob"
        url = f"{repo}/{kind}/{branch}/{path.rstrip('/')}"
        if line and not is_dir:
            url += f"#L{line}"
        return url

    @env.macro
    def src(path, line=None):
        """Link to a source file or directory on the configured fork.

        Path ending with "/" renders a tree URL; otherwise a blob URL.
        Pass line for a #L<n> anchor. Link text is the path (with
        :line suffix when applicable).
        """
        text = f"{path}:{line}" if (line and not path.endswith("/")) else path
        return f"[`{text}`]({_blob_url(path, line)})"

    @env.macro
    def mod(name, line=None):
        """Link an Elixir module name to its source file.

        Auto-derives Logflare.X.Y → lib/logflare/x/y.ex via
        CamelCase → snake_case, with overrides for irregular cases.
        Link text is the module name itself.
        """
        return f"[`{name}`]({_blob_url(_module_to_path(name), line)})"
