def define_env(env):
    repo = env.variables["code_repo"]
    branch = env.variables["code_branch"]

    @env.macro
    def src(path, line=None):
        """Render a markdown link to source code on GitHub.

        Path ending with "/" is treated as a directory (tree URL);
        otherwise as a file (blob URL). Pass line for #L<n> anchor.
        Link text is the path (with :line suffix when applicable),
        wrapped in backticks for monospace rendering.
        """
        is_dir = path.endswith("/")
        kind = "tree" if is_dir else "blob"
        clean_path = path.rstrip("/")
        url = f"{repo}/{kind}/{branch}/{clean_path}"
        text = path
        if line and not is_dir:
            url += f"#L{line}"
            text = f"{path}:{line}"
        return f"[`{text}`]({url})"
