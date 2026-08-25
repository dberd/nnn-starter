{
  config,
  pkgs,
  ...
}: {
  # GTK colours come from Noctalia, not Stylix — the same split already used for
  # the terminal in ./ghostty.nix, and for the same reason: Noctalia recomputes
  # its palette at runtime, so GTK windows follow a wallpaper or scheme change
  # immediately, while Stylix bakes colours into the store at build time and can
  # only catch up on the next rebuild.
  #
  # Turning the target off is what makes the handover clean rather than a fight.
  # Stylix's gtk target writes gtk-3.0/gtk.css and gtk-4.0/gtk.css itself, and
  # Noctalia's template would have to delete those store symlinks to get its own
  # @import in — which home-manager then undoes on the next switch. With the
  # target off (and gtk4.theme null, below) home-manager writes neither file, so
  # Noctalia simply owns them. settings.ini stays home-manager's.
  #
  # Enabled template ids live in modules/home/noctalia.nix.
  stylix.targets.gtk.enable = false;

  gtk = {
    enable = true;

    # Stylix used to supply this, and picked plain "adw-gtk3" — the *light*
    # variant, with no gtk-application-prefer-dark-theme anywhere. GTK4 apps got
    # away with it because libadwaita follows the portal's color-scheme, but
    # plain GTK3 reads settings.ini and came out light. Both halves are fixed
    # here: the dark variant of the very same package, plus the explicit hint.
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };

    # adw-gtk3 exists to make GTK3 look like libadwaita; GTK4 already has the
    # real thing, so pointing gtk4 at this theme is legacy behaviour that only
    # adds an @import to gtk-4.0/gtk.css. Null drops the import — and with it
    # the last reason home-manager would write that file at all.
    gtk4.theme = null;

    # Font still comes from Stylix, so there is one source of truth for it even
    # though the colours have moved.
    font = {
      inherit (config.stylix.fonts.sansSerif) package name;
      size = config.stylix.fonts.sizes.applications;
    };

    # Icon theme, which Stylix never touched. Without it Nautilus falls back to
    # the bare hicolor/Adwaita defaults and looks plain. Papirus is the most
    # complete Linux icon set (full folder + mime coverage); the plain prebuilt
    # package comes straight from the binary cache, whereas recolouring it via
    # `.override { color = ...; }` would force a slow from-source rebuild of the
    # whole set.
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };

    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
  };

  # Deliberately no dconf.settings for org/gnome/desktop/interface here: the GTK
  # template's apply.sh sets gtk-theme and color-scheme over gsettings whenever
  # the mode changes, so declaring them would just fight it.
}
