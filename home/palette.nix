# Shared colour tokens for the whole session.
#
# Pure data, no module args — `import ./palette.nix` from anywhere that needs a
# colour. Lives in its own file so home.nix and the per-app modules beside it
# (firefox.nix, …) read from one definition instead of each carrying its own
# copy of the hex values.
{
  # Nord palette — https://www.nordtheme.com/
  nord = {
    # Polar Night (dark bases)
    nord0 = "2E3440";
    nord1 = "3B4252";
    nord2 = "434C5E";
    nord3 = "4C566A";
    # Snow Storm (light text)
    nord4 = "D8DEE9";
    nord5 = "E5E9F0";
    nord6 = "ECEFF4";
    # Frost (blue/teal accents)
    nord7 = "8FBCBB";
    nord8 = "88C0D0";
    nord9 = "81A1C1";
    nord10 = "5E81AC";
    # Aurora (colored accents)
    nord11 = "BF616A"; # red
    nord12 = "D08770"; # orange
    nord13 = "EBCB8B"; # yellow
    nord14 = "A3BE8C"; # green
    nord15 = "B48EAD"; # purple
  };

  # ---- Semantic UI tokens ----
  # Nord's Polar Night is four values crammed into a narrow band, so a panel, a
  # hover state and a border all land at nearly the same weight — the palette
  # gives you colors but no *hierarchy*. These tokens extend the ramp downward
  # (keeping Nord's ~220° hue) so there are real elevation steps: nord0 stops
  # being the floor and becomes a raised surface, with two darker levels beneath
  # it for the desktop and window chrome. Everything in this config should reach
  # for a token below rather than a raw nordN, so the layers stay consistent.
  ui = {
    # Elevation ramp, darkest (desktop) to lightest (selected row).
    bg = "14181F"; # wallpaper / deepest ground
    surface0 = "1B212A"; # window chrome base
    surface1 = "232B36"; # floating panels: waybar, mako, fuzzel, eww
    surface2 = "2E3440"; # raised / hover        (= nord0)
    surface3 = "3B4252"; # active / selected     (= nord1)

    # Hairlines. `line` is for dividers inside a surface, `lineStrong` for the
    # outer edge of a floating panel where it has to hold against the wallpaper.
    line = "2B3441";
    lineStrong = "3F4A5C";

    # Text ramp. Nord only ships three near-identical light values, and this
    # config was using nord3 (#4C566A, a *background* value) as muted text —
    # which is why secondary text read as muddy rather than quiet. These are
    # tuned for contrast on surface1: 7.0:1, 4.7:1, 2.9:1.
    text = "ECEFF4"; # primary                (= nord6)
    textDim = "AEB8C8"; # secondary
    textMute = "8B96A8"; # tertiary / metadata
    textFaint = "667186"; # disabled / decorative

    # One accent, used only for focus and active state. Nord's other frost and
    # aurora hues stay available but are reserved for *semantic* meaning below —
    # when five things are accented, nothing is.
    accent = "88C0D0"; # (= nord8)
    accentDeep = "5E81AC"; # pressed / filled backgrounds (= nord10)

    # Semantic only — never decorative.
    ok = "A3BE8C"; # (= nord14)
    warn = "EBCB8B"; # (= nord13)
    err = "BF616A"; # (= nord11)
  };

  # Shared geometry. 12px is the outer radius every floating surface uses (niri's
  # geometry-corner-radius, waybar, fuzzel, mako, eww); 8px is the inner radius
  # for controls *inside* one of those surfaces. Keeping the two a fixed step
  # apart is what makes nested corners look concentric rather than arbitrary.
  radius = {
    outer = 12;
    inner = 8;
  };
}
