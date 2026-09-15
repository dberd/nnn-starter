{
  config,
  lib,
  pkgs,
  username,
  ...
}: let
  # fastfetch's own config, in the one form its Noctalia hook will accept.
  #
  # That hook merges the generated palette into this file with jq and writes the
  # result back, so two things have to hold: the file must already exist (it
  # refuses to create one and says so), and it must be STRICT JSON — it checks
  # with `jq empty` first and bails with a clear message on the comments and
  # trailing commas that .jsonc otherwise allows. Hence builtins.toJSON rather
  # than a hand-written file with comments in it.
  #
  # `logo` and `display` are deliberately absent: those are exactly the two
  # objects the hook fills in.
  # btop's hook refuses to work on a file that is not there:
  #
  #   if [ ! -f "$config_file" ]; then
  #       echo "Warning: btop config file not found …" >&2; exit 0
  #   fi
  #
  # and after the Stylix target came off, home-manager stops writing btop.conf
  # and removes the one it had — so without this the very first templates-apply
  # would quietly do nothing. btop only writes a config of its own when it
  # exits, so "just run btop once" would be the alternative, which is a footgun
  # rather than a configuration.
  #
  # One key is enough: btop defaults everything it does not find, and rewrites
  # the whole file on exit anyway. Naming the theme here also means the hook's
  # first branch matches and it has no work to do at all.
  btopConfig = pkgs.writeText "btop.conf" ''
    color_theme = "noctalia"
  '';

  fastfetchConfig = pkgs.writeText "fastfetch-config.jsonc" (builtins.toJSON {
    "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json";
    modules = [
      "title"
      "separator"
      "os"
      "host"
      "kernel"
      "uptime"
      "packages"
      "shell"
      "de"
      "wm"
      "terminal"
      "cpu"
      "gpu"
      "memory"
      "swap"
      "disk"
      "localip"
      "break"
      "colors"
    ];
  });
in {
  # ── Tools with a home-manager program module ──────────────────────────────
  # Using programs.* (rather than raw packages) gets us shell integration and
  # Stylix theming for free.

  programs.lsd = {
    enable = true;
    settings = {
      date = "relative";
      icons.when = "auto";
    };
  };

  programs.bat.enable = true;
  programs.btop.enable = true;
  programs.ripgrep.enable = true;
  programs.fd.enable = true;
  programs.jq.enable = true;

  # zellij, themed by Noctalia. This is the easy shape of template: it has no
  # apply.sh at all, so it only renders ~/.config/zellij/themes/noctalia.kdl and
  # never touches config.kdl. That means config.kdl can stay home-manager's —
  # all we owe the template is the one line that selects its theme, the same
  # deal as `theme = "noctalia"` in ./ghostty.nix.
  #
  # Setting `settings` at all is what makes home-manager start writing
  # config.kdl. Two consequences worth knowing:
  #
  #   - the 22 KB config.kdl zellij dumped for itself gets moved aside to
  #     config.kdl.hm-bak on the next activation (backupFileExtension in
  #     flake.nix). Nothing is lost: every `theme` line in it is commented out
  #     and the rest is zellij's own defaults, which it applies anyway.
  #   - zellij customisation now goes through here rather than that file.
  #
  # Honest limit: a RUNNING zellij will not repaint on a palette switch. It
  # watches config.kdl, and what changes is themes/noctalia.kdl. The template
  # ships a `touch config.kdl` post_hook for exactly this and upstream has it
  # commented out — and it could not work here anyway, config.kdl being a store
  # symlink. New sessions pick the new palette up immediately, which is still a
  # rebuild less than Stylix needed.
  programs.zellij = {
    enable = true;
    settings.theme = "noctalia";
  };

  # Off, and it was never doing anything in the first place: this target writes
  # themes/stylix.kdl but does not set `theme`, so nothing ever selected it —
  # zellij has been running unthemed. Now the file would also sit next to
  # noctalia.kdl as a decoy.
  stylix.targets.zellij.enable = false;

  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
    defaultCommand = "fd --type f --hidden --exclude .git";
  };

  # ── Colour handed to Noctalia ─────────────────────────────────────────────
  # These three follow a palette switch at runtime instead of waiting for a
  # rebuild; see theme.templates in ./noctalia.nix for the whole picture.
  #
  # Turning the target off is the entire mechanism, not just half of it. Each of
  # these home-manager modules writes its config file only when its settings are
  # non-empty — `xdg.configFile."bat/config" = mkIf (cfg.config != {})`,
  # likewise btop's btop.conf — and Stylix was the only thing putting anything
  # in them. Off, home-manager writes no file, the path stops being a read-only
  # store symlink, and the template's hook can create and edit it. Leave one on
  # and the hook dies on `touch: Permission denied` before it even reads the
  # file.
  #
  # fzf is different in kind: it has no config file, and Stylix was setting
  # programs.fzf.colors, which becomes --color flags in FZF_DEFAULT_OPTS. The
  # template writes a fish snippet that sets the same variable, and ./fish.nix
  # sources it; two owners of one variable is why this has to be off.
  stylix.targets.bat.enable = false;
  stylix.targets.btop.enable = false;
  stylix.targets.fzf.enable = false;

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    options = ["--cmd cd"]; # `cd` becomes smart, keeps muscle memory.
  };
  # home-manager loads `zoxide init` early in the shell init, but direnv hooks
  # in afterwards. zoxide's startup "doctor" heuristic wants to be initialized
  # last, so it prints a one-off "possible configuration issue" warning even
  # though the hook is registered and tracking works fine. Silence it.
  home.sessionVariables._ZO_DOCTOR = "0";

  programs.tealdeer = {
    enable = true;
    settings.updates.auto_update = true;
  };

  # ── Everything else ───────────────────────────────────────────────────────
  home.packages = with pkgs; [
    # navigation / files
    eza # alternative listing to lsd, handy for `eza --tree`
    # TUI file manager. Stays a raw package rather than `programs.yazi` for the
    # same reason as cava in ./apps.nix: Noctalia's template rewrites
    # ~/.config/yazi/theme.toml, and the module would own that path.
    yazi

    # system / inspection
    dust # disk usage (du replacement)
    duf # disk free (df replacement)
    procs # process viewer (ps replacement)
    bandwhich # per-process bandwidth
    gping # ping with a graph
    traceroute
    fastfetch # system summary (neofetch's successor)
    less # explicit: bat replaces `cat`, but pagers still shell out to less

    # data / misc
    yq-go # yaml/json/xml processor
    curlie # httpie-like curl frontend
    sd # sed-like find & replace

    # nix workflow
    nix-output-monitor # pretty build output (`nom`)
    alejandra # formatter
    devenv # per-project dev environments (`use devenv` in .envrc)
  ];

  # nh is a nicer frontend for nixos-rebuild + garbage collection. Point it at
  # wherever you keep this flake checked out.
  programs.nh = {
    enable = true;
    flake = "/home/${username}/nixos-config";
  };

  # Seed fastfetch's config, but only when it is not already there.
  #
  # Same shape and the same reason as the ghostty theme seed in ./ghostty.nix:
  # the file has to be a real writable copy, because Noctalia's hook rewrites it
  # on every palette change, and `home.file` would make it a store symlink the
  # hook cannot touch — literally, `touch` is its first statement.
  #
  # `-e` rather than `-f` so a symlink left by an older generation counts as
  # present and is replaced deliberately rather than silently clobbered.
  #
  # The cost of seed-only-once is the usual one: editing fastfetchConfig above
  # will NOT reach a machine that already has the file. Delete it and rebuild,
  # or edit it in place — it is yours from the first activation onwards.
  home.activation.fastfetchConfigSeed = lib.hm.dag.entryAfter ["writeBoundary"] ''
    cfg="${config.xdg.configHome}/fastfetch/config.jsonc"
    if [ ! -e "$cfg" ]; then
      run mkdir -p $VERBOSE_ARG "$(dirname "$cfg")"
      run install -m644 $VERBOSE_ARG ${fastfetchConfig} "$cfg"
    fi
  '';

  # Same again for btop — see the btopConfig binding above for why its hook
  # cannot bootstrap itself. Runs after linkGeneration, so the btop.conf
  # home-manager used to own has already been removed by the time this looks.
  home.activation.btopConfigSeed = lib.hm.dag.entryAfter ["linkGeneration"] ''
    cfg="${config.xdg.configHome}/btop/btop.conf"
    if [ ! -e "$cfg" ]; then
      run mkdir -p $VERBOSE_ARG "$(dirname "$cfg")"
      run install -m644 $VERBOSE_ARG ${btopConfig} "$cfg"
    fi
  '';
}
