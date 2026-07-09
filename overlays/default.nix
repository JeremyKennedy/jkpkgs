# Package overrides and wrappers for reusable fixes.
# Consumed via `inputs.jkpkgs.overlays.default`.
final: prev: {
  # OrcaSlicer 2.4.2 — bump from nixpkgs' 2.4.1
  # nixpkgs' wrapper omits the GTK3 gsettings schemas, so the
  # app SIGABRTs ("Settings schema 'org.gtk.Settings.FileChooser' is not
  # installed") the instant it opens any file-chooser dialog. Every other
  # GTK3 app (e.g. qalculate-gtk) prepends the gtk3 schema dir to
  # XDG_DATA_DIRS; do the same here. Wrap via symlinkJoin so we reuse the
  # cached upstream binary instead of triggering a full source rebuild.
  #
  # Also adds GStreamer codec plugins so the WebKitGTK webview can play
  # H.264 video (e.g. camera streams, previews). gst-libav provides the
  # reliable avdec_h264 software decoder; gst-plugins-bad/good/base
  # are already linked at build time but need to be in the runtime
  # GST_PLUGIN_SYSTEM_PATH_1_0 for the plugin scanner to find them.
  orca-slicer = let
    base = prev.orca-slicer.overrideAttrs (old: {
      version = "2.4.2";
      src = final.fetchFromGitHub {
        owner = "OrcaSlicer";
        repo = "OrcaSlicer";
        tag = "v2.4.2";
        hash = "sha256-gUwLC0XkeohEdL0EScdOrA8MWXGuR8kUfezoQsk9i/A=";
      };
    });

    # GStreamer plugins needed at runtime for H.264 video decode in the
    # WebKitGTK webview. gst-libav provides the software avdec_h264 decoder;
    # the others are already linked at build time but the plugin scanner
    # needs them in GST_PLUGIN_SYSTEM_PATH_1_0 to discover them.
    gstPlugins = with final.gst_all_1; [
      gstreamer
      gst-plugins-base
      gst-plugins-good
      gst-plugins-bad
      gst-libav
    ];

    gstPluginPath = final.lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" gstPlugins;
  in
  final.symlinkJoin {
    name = "orca-slicer-${base.version}";
    paths = [ base ];
    nativeBuildInputs = [ final.makeBinaryWrapper ];
    postBuild = ''
      wrapProgram $out/bin/orca-slicer \
        --prefix XDG_DATA_DIRS : "${final.gtk3}/share/gsettings-schemas/gtk+3-${final.gtk3.version}" \
        --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${gstPluginPath}" \
        --set GST_PLUGIN_SCANNER_1_0 "${final.gst_all_1.gstreamer}/libexec/gstreamer-1.0/gst-plugin-scanner"
    '';
    meta = base.meta // {
      mainProgram = "orca-slicer";
    };
  };
}