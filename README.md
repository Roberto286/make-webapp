# make-webapp

Create desktop launchers for Chromium web apps from Fish, with a separate browser profile for each app.

## Requirements

- Fish (tested with 4.6.0).
- `curl` and standard Linux tools: `mkdir`, `mktemp`, `mv`, `rm`, and `chmod`.
- Native Chromium available as `chromium`, or the `org.chromium.Chromium` Flatpak.
- Optional: `update-desktop-database` from desktop-file-utils.

## Install with Fisher

```fish
fisher install roberto286/make-webapp
```

[Fisher](https://github.com/jorgebucaran/fisher) installs plugins directly from GitHub; no central registry is required.

## Usage

```fish
make-webapp "WhatsApp" "https://web.whatsapp.com"
make-webapp "GitHub Web" "https://github.com"
```

The display name preserves the supplied app name. A lowercase slug determines the paths:

- Launcher: `~/.local/share/applications/webapp-<slug>.desktop`
- Icon: `~/.local/share/icons/webapp-<slug>.png`
- Chromium profile: `~/.config/chromium-<slug>` (created on first launch)

Native Chromium takes precedence. Otherwise the launcher uses `flatpak run org.chromium.Chromium` with access to the app's profile directory. No global Flatpak override is installed.

Favicons are downloaded from [icon.horse](https://icon.horse). This sends the site's domain to that service; image resolution depends on availability. If downloading fails, the launcher uses the native or Flatpak Chromium system icon.

When available, `update-desktop-database` runs after creating the launcher. Launchers may also need their app list refreshed. Running the command again with the same slug replaces that launcher's configuration and icon while keeping its browser profile.

## Update or uninstall

```fish
fisher update roberto286/make-webapp
fisher remove roberto286/make-webapp
```

Uninstalling the plugin removes the Fish function, not the launchers, icons, or browser profiles it generated. Remove those separately only when no longer needed; profiles may contain login sessions and other browser data.

## Check

```sh
python3 tests/smoke.py
```

The check needs Fish and Python 3 with PyGObject/Gio. It uses temporary directories and test executables; it does not launch a browser or access the network.

## License

MIT. See [LICENSE](LICENSE).
