import re

# Modules whose source file path can't be auto-derived from the
# CamelCase → snake_case convention (e.g., live in a different
# directory, or are named after the umbrella supervisor).
MODULE_OVERRIDES = {
    "Logflare.LogEvent": "lib/logflare/logs/log_event.ex",
    "Logflare.LogEvent.TypeDetection": "lib/logflare/logs/log_event/type_detection.ex",
    "Logflare.Supervisor": "lib/logflare/application.ex",
}


def _strip_function_suffix(name):
    """Drop trailing function-like segments (`module.foo/0`, `module.foo!`).

    A segment is treated as a function (not a sub-module) when its first
    character is lowercase or it contains a "/". Walks right-to-left so
    "Logflare.LogEvent.TypeDetection" stays intact while
    "Logflare.SingleTenant.single_tenant?/0" reduces to "Logflare.SingleTenant".
    """
    parts = name.split(".")
    while parts and (parts[-1][0].islower() or "/" in parts[-1]):
        parts.pop()
    return ".".join(parts)


def _module_to_path(name):
    name = _strip_function_suffix(name)
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
