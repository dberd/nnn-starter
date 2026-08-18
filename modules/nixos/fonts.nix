{pkgs, ...}: {
  fonts = {
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono # JetBrains Mono + Nerd Font glyphs (mono default).
      maple-mono.NF # Kept as the monospace fallback (upstream's default).
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];

    enableDefaultPackages = true;

    fontconfig.defaultFonts = {
      # fontconfig walks this list in order, so Maple covers any glyph
      # JetBrains Mono NF happens to be missing.
      monospace = ["JetBrainsMono Nerd Font" "Maple Mono NF"];
      sansSerif = ["Noto Sans"];
      serif = ["Noto Serif"];
      emoji = ["Noto Color Emoji"];
    };
  };
}
