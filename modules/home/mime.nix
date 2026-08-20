{...}: {
  # Which GUI application opens a file when something else asks the desktop to
  # open it — a double-click in Nautilus, "open with default", `xdg-open` from a
  # script. In the terminal, $EDITOR remains neovim (modules/home/neovim.nix).
  #
  # This lived in zed.nix until Zed was removed; the associations were never
  # about Zed, they point at VSCodium (modules/home/vscodium.nix). It is also
  # the module that turns `xdg.mimeApps` on — media.nix adds the image/audio/
  # video entries to the same attrset without re-setting `enable`, which would
  # be a conflicting definition.
  #
  # The zen-browser module (modules/home/apps.nix) also claims text/plain, but
  # only with lib.mkDefault, so these plain assignments win. text/html and
  # application/json stay with Zen.
  xdg.mimeApps = {
    enable = true;
    defaultApplications = let
      editor = "codium.desktop";
    in {
      "text/plain" = editor;
      "text/markdown" = editor;
      "text/x-readme" = editor;
      "text/x-python" = editor;
      "text/x-shellscript" = editor;
      "text/x-csrc" = editor;
      "text/x-chdr" = editor;
      "text/rust" = editor;
      "application/x-shellscript" = editor;
      "application/toml" = editor;
      "application/x-yaml" = editor;
      "application/xml" = editor;
    };
  };
}
