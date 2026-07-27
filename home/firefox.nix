{ ... }:

let
  inherit (import ./palette.nix) ui radius;

  # Chrome font. The rest of the session's chrome is JetBrains Mono (waybar,
  # fuzzel, mako, eww), so the browser frame uses it too — a proportional UI
  # sans here is the single loudest tell that Firefox isn't part of the set.
  # 13px matches waybar; monospace runs wide, so this is a notch under the
  # ~15px GTK menu size rather than matched to it.
  chromeFont = ''"JetBrainsMono Nerd Font", "Symbols Nerd Font", monospace'';

  # ---- Firefox chrome (userChrome.css) ----
  #
  # Firefox's own dark theme is built on a purple-leaning near-black —
  # #1c1b22 / #2b2a33 / #42414d. Sat next to waybar and the eww panels, which
  # are blue-grey at #1B212A / #232B36 / #2E3440, it reads as a window borrowed
  # from a different machine: same darkness, wrong hue, wrong radii, wrong font.
  # This maps the browser onto the session's elevation ramp instead.
  #
  # Nearly all of the work happens by overriding Firefox's *theme variables*
  # rather than by styling widgets. The variables are a broad, fairly stable
  # surface — one assignment recolours every panel, menu and doorhanger at once
  # — while the XUL element tree churns between releases. The structural rules
  # further down are the exceptions, and each degrades to a no-op if Firefox
  # renames the node it targets.
  #
  # !important is not optional. An active theme sets these same variables as
  # inline styles on :root, and no stylesheet rule outranks an inline style.
  userChrome = ''
    /* ── Session tokens (mirrors home/palette.nix) ───────────────────────── */
    :root {
      --nx-bg:          #${ui.surface0};   /* window chrome base            */
      --nx-panel:       #${ui.surface1};   /* floating panels, urlbar fill  */
      --nx-raised:      #${ui.surface2};   /* hover                         */
      --nx-active:      #${ui.surface3};   /* selected                      */
      --nx-line:        #${ui.line};       /* divider inside a surface      */
      --nx-edge:        #${ui.lineStrong}; /* outer edge of a floating panel*/
      --nx-text:        #${ui.text};
      --nx-dim:         #${ui.textDim};
      --nx-mute:        #${ui.textMute};
      --nx-faint:       #${ui.textFaint};
      --nx-accent:      #${ui.accent};
      --nx-accent-deep: #${ui.accentDeep};
      --nx-err:         #${ui.err};

      --nx-radius:      ${toString radius.inner}px;   /* controls           */
      --nx-radius-out:  ${toString radius.outer}px;   /* floating surfaces  */

      /* The gap between the chrome and the page card below. Half niri's window
         gap (16px): this is a seam inside one window, not a gap between two. */
      --nx-gap:         8px;

      /* Motion, lifted from niri's animation block — window-close is 130ms on
         an ease-out curve. Firefox's stock chrome transitions are roughly
         double that, which is what makes hovering a tab feel like it lags
         behind hovering anything else in the session. */
      --nx-motion:      130ms cubic-bezier(0.16, 1, 0.3, 1);

      /* niri's shadow, exactly: softness 14, spread 0, offset y 3, #00000099.
         Firefox's panels float above the window the same way the window floats
         above the desktop, so they cast the same shadow. */
      --nx-shadow:      0 3px 14px #00000099;
    }

    /* ── Firefox's theme variables, remapped ─────────────────────────────── */
    :root {
      color-scheme: dark;

      /* Frame + toolbars */
      --lwt-accent-color: var(--nx-bg) !important;
      --lwt-accent-color-inactive: var(--nx-bg) !important;
      --lwt-text-color: var(--nx-dim) !important;
      --toolbar-bgcolor: var(--nx-bg) !important;
      --toolbar-color: var(--nx-dim) !important;
      --tabpanel-background-color: var(--nx-bg) !important;

      /* Toolbar buttons. The icons sit at textDim and only reach full strength
         on hover — same "hierarchy by lightness" rule the bar follows. */
      --toolbarbutton-icon-fill: var(--nx-dim) !important;
      --lwt-toolbarbutton-icon-fill: var(--nx-dim) !important;
      --toolbarbutton-hover-background: var(--nx-raised) !important;
      --toolbarbutton-active-background: var(--nx-active) !important;
      --toolbarbutton-border-radius: var(--nx-radius) !important;

      /* Address bar */
      --toolbar-field-background-color: var(--nx-panel) !important;
      --toolbar-field-focus-background-color: var(--nx-panel) !important;
      --toolbar-field-color: var(--nx-text) !important;
      --toolbar-field-focus-color: var(--nx-text) !important;
      --toolbar-field-border-color: transparent !important;
      --toolbar-field-focus-border-color: var(--nx-accent) !important;
      --urlbar-box-bgcolor: var(--nx-raised) !important;
      --urlbar-box-focus-bgcolor: var(--nx-active) !important;
      --urlbar-box-hover-bgcolor: var(--nx-active) !important;
      --urlbar-box-text-color: var(--nx-dim) !important;

      /* Tabs */
      --tab-selected-bgcolor: var(--nx-active) !important;
      --tab-selected-textcolor: var(--nx-text) !important;
      --tab-hover-background-color: var(--nx-raised) !important;
      --tab-border-radius: var(--nx-radius) !important;
      /* Firefox marks the selected tab with a coloured line along one edge.
         Selection is carried by the raised surface plus full-strength text
         instead (see the vertical-tab rule below), so this is switched off. */
      --lwt-tab-line-color: transparent !important;

      /* Panels, doorhangers, menus — the fuzzel/mako surface treatment:
         surface1 fill, one hairline at lineStrong, 12px outer radius. */
      --arrowpanel-background: var(--nx-panel) !important;
      --arrowpanel-color: var(--nx-dim) !important;
      --arrowpanel-border-color: var(--nx-edge) !important;
      --arrowpanel-dimmed: var(--nx-raised) !important;
      --arrowpanel-dimmed-further: var(--nx-active) !important;
      --panel-separator-color: var(--nx-line) !important;
      --panel-border-color: var(--nx-edge) !important;
      --panel-border-radius: var(--nx-radius-out) !important;
      --panel-item-hover-bgcolor: var(--nx-raised) !important;
      --panel-item-active-bgcolor: var(--nx-active) !important;

      /* Sidebar (the revamped one; vertical tabs live in it) */
      --sidebar-background-color: var(--nx-bg) !important;
      --sidebar-text-color: var(--nx-dim) !important;
      --sidebar-border-color: var(--nx-line) !important;

      /* Buttons + focus. The focus ring is the accent and nothing else is —
         same rule as niri's focus ring and waybar's active workspace. */
      --button-bgcolor: var(--nx-raised) !important;
      --button-hover-bgcolor: var(--nx-active) !important;
      --button-active-bgcolor: var(--nx-active) !important;
      --button-primary-bgcolor: var(--nx-accent-deep) !important;
      --button-primary-hover-bgcolor: var(--nx-accent) !important;
      --button-primary-color: var(--nx-text) !important;
      --focus-outline-color: var(--nx-accent) !important;
      --link-color: var(--nx-accent) !important;
      --link-color-hover: var(--nx-text) !important;
      --error-text-color: var(--nx-err) !important;

      --newtab-background-color: var(--nx-bg) !important;
    }

    /* ── Type ────────────────────────────────────────────────────────────── */
    /* Set once on the root and inherited. A few widgets hard-code `font: menu`,
       so those are named explicitly rather than reaching for a `*` selector. */
    :root,
    menupopup, menu, menuitem, panel, .panel-header, toolbarbutton,
    .urlbarView, #urlbar-input, #searchbar, findbar, tab, .tab-label {
      font-family: ${chromeFont} !important;
    }
    :root { font-size: 13px; }

    /* ── Window frame ────────────────────────────────────────────────────── */
    /* niri draws the window edge (prefer-no-csd, 12px corners, 2px focus ring),
       so Firefox's own minimise/maximise/close buttons are a second, mismatched
       set of window controls — and the drag spacers reserve horizontal room for
       a titlebar that no longer exists under a tiling WM.
       #toolbar-menubar is the File/Edit/View/History strip. It hides itself
       when its `autohide` attribute is "true", but that attribute lives in the
       profile's xulstore.json — mutable state this config can't reach, and in
       this profile it is stuck at the literal string "-moz-missing" rather than
       "true", so Firefox renders the bar permanently. Hiding it in CSS is the
       declarative fix; every one of those menus is also in the ≡ panel. */
    #toolbar-menubar,
    .titlebar-buttonbox-container,
    .titlebar-spacer {
      display: none !important;
    }

    /* The page card below is inset by --nx-gap on its left, right and bottom.
       The toolbar sits above it and was flush against the window edge, so the
       chrome was the one thing in the window with no margin — which is what
       made the top read as cramped even though the row itself is a normal
       height. Same inset on all four sides now: everything lives inside one
       consistent margin. */
    #navigator-toolbox {
      background-color: var(--nx-bg) !important;
      border-bottom: none !important;
      padding-top: var(--nx-gap) !important;
    }
    /* Firefox's default is a soft drop shadow under the nav bar — the only
       blurred edge in a session built entirely on 1px hairlines, and it reads
       as a second, fuzzier border once niri has drawn a real one. The page
       card below supplies the separation instead. */
    #nav-bar {
      box-shadow: none !important;
      border: none !important;
      padding-block: 4px !important;
      padding-inline: calc(var(--nx-gap) - 2px) !important;
    }
    #nav-bar toolbarseparator { display: none !important; }

    /* ── The page as a card ──────────────────────────────────────────────── */
    /* The one structural change, and the reason the window stops reading as
       "toolbars bolted to a webpage": the content is inset and given the inner
       radius plus a lineStrong hairline, so the page floats inside the chrome
       exactly the way a window floats on the wallpaper and a panel floats in a
       window. Same rule at every level, so the 12px outer corner and the 8px
       inner corner look concentric rather than coincidental.
       This is also why the toolbar and sidebar hairlines above were dropped —
       with a gap doing the separating, a border as well is one edge too many. */
    .browserStack {
      margin: 0 var(--nx-gap) var(--nx-gap) var(--nx-gap) !important;
      border-radius: var(--nx-radius) !important;
      overflow: hidden !important;
      box-shadow: 0 0 0 1px var(--nx-edge) !important;
    }
    #tabbrowser-tabpanels { background-color: var(--nx-bg) !important; }

    /* Fullscreen and PiP want every pixel and have no chrome to sit inside. */
    :root[inFullscreen] .browserStack,
    :root[chromehidden~="toolbar"] .browserStack {
      margin: 0 !important;
      border-radius: 0 !important;
      box-shadow: none !important;
    }

    /* ── Address bar ─────────────────────────────────────────────────────── */
    /* Reads as fuzzel's input: a recessed surface1 field with a hairline, which
       turns accent on focus. Firefox's stock focus state is a wide blue glow —
       the only soft-edged shadow anywhere in this session, and the reason the
       bar drew the eye every time it was clicked. */
    #urlbar-background,
    #searchbar {
      background-color: var(--nx-panel) !important;
      border: 1px solid var(--nx-line) !important;
      border-radius: var(--nx-radius) !important;
    }
    #urlbar[focused="true"] > #urlbar-background {
      border-color: var(--nx-accent) !important;
      box-shadow: none !important;
      outline: none !important;
    }
    #urlbar-input::placeholder { color: var(--nx-faint) !important; }

    /* The suggestions dropdown is the browser's launcher, so it gets the
       launcher's treatment: floating panel radius, one edge hairline, and
       selection carried by surface3 rather than by a tinted row. */
    .urlbarView {
      background-color: var(--nx-panel) !important;
      border: 1px solid var(--nx-edge) !important;
      border-radius: var(--nx-radius-out) !important;
      padding: 6px !important;
    }
    .urlbarView-row > .urlbarView-row-inner,
    .urlbarView-row > span {
      border-radius: var(--nx-radius) !important;
    }
    .urlbarView-row[selected] > .urlbarView-row-inner,
    .urlbarView-row:hover > .urlbarView-row-inner {
      background-color: var(--nx-active) !important;
      color: var(--nx-text) !important;
    }
    .urlbarView-url { color: var(--nx-mute) !important; }
    /* The fuzzy-match highlight is the one accent in the list — same call as
       fuzzel's `match` colour, and it stays legible on a selected row. */
    .urlbarView-title strong,
    .urlbarView-url strong {
      color: var(--nx-accent) !important;
      font-weight: normal !important;
    }

    /* ── Vertical tabs ───────────────────────────────────────────────────── */
    #sidebar-main,
    #sidebar-box {
      background-color: var(--nx-bg) !important;
      border-inline-end: none !important;   /* the page card's gap separates */
    }
    /* A long tab list is the one place in the browser that scrolls constantly;
       a full-width scrollbar beside it is a second vertical rule competing
       with the tabs themselves. */
    #vertical-tabs,
    #tabbrowser-tabs[orient="vertical"] {
      scrollbar-width: thin !important;
    }

    /* Row geometry. Tabs are the list you scan most, so they get the roomiest
       treatment in the chrome: a taller row than Firefox ships, and the pill
       inset from the rail edges so it reads as a selectable row rather than a
       full-bleed band — the same shape as a fuzzel result. */
    #tabbrowser-tabs[orient="vertical"] { --tab-min-height: 34px !important; }
    #tabbrowser-tabs[orient="vertical"] .tab-background {
      border-radius: var(--nx-radius) !important;
      margin-block: 2px !important;
      margin-inline: 4px !important;
    }
    #tabbrowser-tabs[orient="vertical"] .tab-content {
      padding-inline: 10px !important;
    }
    #tabbrowser-tabs[orient="vertical"] .tabbrowser-tab:hover .tab-background:not([selected]) {
      background-color: var(--nx-raised) !important;
    }
    /* Selection is the raised surface plus full-strength text, and nothing
       else. This is the same call eww's device rows make (.dev.active) and for
       the same reason: in a list where every row looks alike, one extra mark
       on the selected row is the mark you end up looking at instead of the
       row. The elevation step is the signal. */
    #tabbrowser-tabs[orient="vertical"] .tab-background[selected] {
      background-color: var(--nx-active) !important;
      box-shadow: none !important;
    }
    #tabbrowser-tabs[orient="vertical"] .tabbrowser-tab:not([selected]) .tab-label {
      color: var(--nx-mute) !important;
    }
    #tabbrowser-tabs[orient="vertical"] .tabbrowser-tab[selected] .tab-label {
      color: var(--nx-text) !important;
    }
    /* One close button per row, times twenty rows, is twenty ✕ glyphs asking
       for attention in a list you read by title. `visibility` rather than
       `display` so revealing one on hover doesn't reflow the label beside it. */
    #tabbrowser-tabs[orient="vertical"] .tab-close-button { visibility: hidden !important; }
    #tabbrowser-tabs[orient="vertical"] .tabbrowser-tab:hover .tab-close-button,
    #tabbrowser-tabs[orient="vertical"] .tabbrowser-tab[selected] .tab-close-button {
      visibility: visible !important;
    }

    /* ── Motion ──────────────────────────────────────────────────────────── */
    /* Only the hover/selection states, and only on the properties that were
       already animating. The point is to bring Firefox's timing onto niri's
       curve, not to add movement that wasn't there. */
    .tab-background,
    toolbarbutton,
    #urlbar-background,
    .urlbarView-row-inner {
      transition:
        background-color var(--nx-motion),
        border-color var(--nx-motion),
        box-shadow var(--nx-motion) !important;
    }

    /* ── Panels ──────────────────────────────────────────────────────────── */
    /* Firefox's own panel shadow is broad and soft; niri's is short and dense
       so surfaces read as sitting *on* something rather than hazing into it.
       Same reasoning as the shadow block in niri/config.kdl. */
    panel::part(content),
    menupopup::part(content),
    .panel-arrowcontent {
      box-shadow: var(--nx-shadow) !important;
      border-radius: var(--nx-radius-out) !important;
      border: 1px solid var(--nx-edge) !important;
    }

    /* ── Odds and ends that are visible constantly ───────────────────────── */
    /* Link-target popup, bottom-left. Stock is a bare light-grey slab. */
    #statuspanel-label {
      background-color: var(--nx-panel) !important;
      color: var(--nx-mute) !important;
      border: 1px solid var(--nx-line) !important;
      border-top-right-radius: var(--nx-radius) !important;
      padding: 3px 8px !important;
    }

    findbar {
      background-color: var(--nx-panel) !important;
      border-top: 1px solid var(--nx-line) !important;
      color: var(--nx-dim) !important;
    }

    /* Chrome-side scrollbars (sidebar, panels, about: pages in the frame). */
    :root { scrollbar-color: var(--nx-edge) transparent !important; }
  '';

  # ---- Page content (userContent.css) ----
  # Two jobs: keep about: pages on the same ramp as the chrome, and stop the
  # new-tab page from being the one Firefox-branded rectangle in the session.
  # Web pages themselves are left alone apart from scrollbars — restyling
  # arbitrary sites is how "themed" browsers end up broken.
  userContent = ''
    /* Scrollbars, everywhere. Deliberately *not* !important: a site that styles
       its own scrollbars is making a design decision and wins the cascade,
       while everything else — the overwhelming majority — inherits Nord.
       scrollbar-color is inherited, so :root is enough. */
    :root {
      scrollbar-color: #${ui.lineStrong} transparent;
    }

    /* about:* — preferences, addons, the error pages you actually see. */
    @-moz-document url-prefix("about:") {
      :root {
        --in-content-page-background: #${ui.surface0} !important;
        --in-content-page-color: #${ui.textDim} !important;
        --in-content-box-background: #${ui.surface1} !important;
        --in-content-box-background-odd: #${ui.surface2} !important;
        --in-content-border-color: #${ui.line} !important;
        --in-content-item-hover: #${ui.surface2} !important;
        --in-content-item-selected: #${ui.surface3} !important;
        --in-content-accent-color: #${ui.accent} !important;
        --in-content-link-color: #${ui.accent} !important;
        --in-content-primary-button-background: #${ui.accentDeep} !important;
        --in-content-primary-button-background-hover: #${ui.accent} !important;
        /* Newer design-token names for the same surfaces; Firefox is mid-way
           through the migration, so both sets are set. */
        --background-color-canvas: #${ui.surface0} !important;
        --background-color-box: #${ui.surface1} !important;
        --text-color: #${ui.textDim} !important;
        --border-color-card: #${ui.line} !important;
        --color-accent-primary: #${ui.accentDeep} !important;
        --color-accent-primary-hover: #${ui.accent} !important;
        --focus-outline-color: #${ui.accent} !important;
      }
    }

    /* New tab / home. The stock page is a light-ish card grid with Firefox's
       own accent — the most-seen surface in the browser and the one that least
       looked like it belonged. Cards get the panel treatment: surface1 fill,
       hairline, 8px inner radius. */
    @-moz-document url("about:newtab"), url("about:home"), url("about:privatebrowsing") {
      :root,
      body {
        --newtab-background-color: #${ui.surface0} !important;
        --newtab-background-color-secondary: #${ui.surface1} !important;
        --newtab-text-primary-color: #${ui.textDim} !important;
        --newtab-primary-action-background: #${ui.accentDeep} !important;
        background-color: #${ui.surface0} !important;
      }
      .top-site-outer .tile,
      .card-outer .card {
        background-color: #${ui.surface1} !important;
        border: 1px solid #${ui.line} !important;
        border-radius: ${toString radius.inner}px !important;
      }
      .top-site-outer .title { color: #${ui.textMute} !important; }
      .search-wrapper .search-handoff-button,
      .search-wrapper input {
        background-color: #${ui.surface1} !important;
        border: 1px solid #${ui.line} !important;
        border-radius: ${toString radius.inner}px !important;
        color: #${ui.textDim} !important;
        box-shadow: none !important;
      }
    }
  '';

  # ---- Profile settings (shared across profiles) ----
  settings = {
    # Native vertical tabs + the revamped sidebar (Firefox 136+).
    "sidebar.verticalTabs" = true;
    "sidebar.revamp" = true;
    "browser.aboutConfig.showWarning" = false;

    # Privacy / telemetry.
    "browser.contentblocking.category" = "strict";
    "datareporting.healthreport.uploadEnabled" = false;
    "toolkit.telemetry.enabled" = false;
    "browser.newtabpage.activity-stream.feeds.telemetry" = false;
    "browser.newtabpage.activity-stream.telemetry" = false;

    # ---- Chrome integration with the niri session ----
    # Without this Firefox ignores chrome/userChrome.css entirely.
    "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
    # Never draw a separate titlebar. niri is asked to omit CSD
    # (prefer-no-csd in config.kdl) and draws the window edge itself, but
    # Firefox doesn't always honour that on Wayland — pinning this makes the
    # nav bar the top of the window either way. Its window controls are hidden
    # in userChrome above.
    "browser.tabs.inTitlebar" = 1;
    # Normal density. This was 1 (compact) on the theory that the browser
    # should match waybar's row heights — but waybar is a 34px strip and this
    # is a full window, and compact on top of a 13px monospace chrome font left
    # the toolbar visibly squeezed. Stated explicitly rather than dropped:
    # prefs.js keeps whatever user.js last set, so removing the line would
    # leave the old compact value in place instead of reverting it.
    "browser.uidensity" = 0;
    "browser.compactmode.show" = true;
    # The bookmarks toolbar defaults to "newtab" — visible on the new-tab page
    # and nowhere else, so the whole page jumps down a row every time you open
    # a tab and back up as soon as you navigate. Bookmarks are Mod+G (the
    # fuzzel web-shortcuts launcher) in this session anyway.
    "browser.toolbars.bookmarks.visibility" = "never";
    # Hovering a tab pops a floating card with a screenshot of the page. With
    # vertical tabs the full title is already on screen, so it's a large moving
    # object showing something you can read without it.
    "browser.tabs.hoverPreview.enabled" = false;
    # Drop the "https://" from the address bar. It's on virtually every URL,
    # carries no information when present, and Firefox still shows the full
    # string the moment you focus the field.
    "browser.urlbar.trimHttps" = true;

    # ---- Dark, without gaps ----
    # niri has no settings daemon, so state this outright rather than hoping
    # the portal answer arrives before first paint.
    "ui.systemUsesDarkTheme" = 1;
    "browser.theme.dark-private-windows" = true;
    # 0 = dark. Sites get prefers-color-scheme: dark regardless of how the
    # browser theme resolves, which is what stops a white page from flashing
    # up inside an otherwise dark session.
    "layout.css.prefers-color-scheme.content-override" = 0;
    # The paint *behind* a page while it loads, and the fallback colours for
    # pages that set none. Firefox's default here is its own #1c1b22.
    "browser.display.background_color.dark" = "#${ui.surface0}";
    "browser.display.foreground_color.dark" = "#${ui.text}";

    # ---- New tab: less of Mozilla's storefront ----
    "browser.newtabpage.activity-stream.showSponsored" = false;
    "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
    "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
    "browser.urlbar.suggest.quicksuggest.sponsored" = false;
  };
in
{
  # Firefox — a declarative, OS-managed alternative to Arc/Zen. Two isolated
  # profiles (personal default + work); native vertical tabs, the Nord chrome
  # above, and the telemetry/privacy prefs all apply to both. Zen stays
  # installed (see home.nix) as a fallback. Launch a specific profile from the
  # web-shortcuts launcher, `firefox -P work`, or about:profiles.
  programs.firefox = {
    enable = true;
    profiles = {
      personal = {
        id = 0;
        isDefault = true;
        inherit settings userChrome userContent;
      };
      work = {
        id = 1;
        inherit settings userChrome userContent;
      };
    };
    # Enterprise policies apply to every profile: kill telemetry/Pocket and
    # force-install uBlock Origin straight from AMO (no NUR or extra flake input
    # needed). Add more add-ons by their extension ID + AMO latest-xpi URL.
    policies = {
      DisableTelemetry = true;
      DisablePocket = true;
      ExtensionSettings = {
        "uBlock0@raymondhill.net" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
        };
      };
    };
  };
}
