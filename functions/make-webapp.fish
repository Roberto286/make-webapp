function make-webapp --description 'Create an isolated web app using native or Flatpak Chromium'
    if test (count $argv) -ne 2
        printf 'Error: provide an app name and URL.\nUsage: make-webapp "App Name" "https://URL"\n' >&2
        return 1
    end

    set -l name "$argv[1]"
    set -l url "$argv[2]"
    set -l slug (string lower -- "$name" | string replace -ar '[^\p{L}\p{N}]+' '-' | string trim -c '-')
    if test -z "$slug"
        printf 'Error: the app name must contain at least one letter or digit.\n' >&2
        return 1
    end

    set -l domain (string match -ri --groups-only '^https?://(?:[^/?#@\s]+@)?(\[[0-9a-f:.]+\]|[^/?#:@\s]+)(?::[0-9]+)?(?:[/?#]|$)' -- "$url")
    if test -z "$domain"; or string match -qr '[\x00-\x20\x7f]' -- "$url"
        printf 'Error: use a valid HTTP/HTTPS URL without unencoded spaces.\n' >&2
        return 1
    end

    set -l applications "$HOME/.local/share/applications"
    set -l icons "$HOME/.local/share/icons"
    set -l profile "$HOME/.config/chromium-$slug"
    set -l desktop "$applications/webapp-$slug.desktop"
    set -l icon_path "$icons/webapp-$slug.png"

    # Prefer native Chromium; grant Flatpak access only to this app's profile.
    set -l launcher chromium
    set -l fallback_icon chromium
    if not command -q chromium
        if command -q flatpak; and command flatpak info org.chromium.Chromium >/dev/null 2>&1
            set launcher flatpak run "--filesystem=$profile:create" org.chromium.Chromium
            set fallback_icon org.chromium.Chromium
        else
            printf 'Error: install Chromium natively or as the org.chromium.Chromium Flatpak.\n' >&2
            return 1
        end
    end
    command mkdir -p -- "$applications" "$icons"; or return 1

    # icon.horse also serves subdomains for which Google favicons returns HTTP 404.
    set -l icon "$fallback_icon"
    set -l temporary (command mktemp "$icons/.webapp-$slug.XXXXXX"); or return 1
    if command curl --fail --location --silent --show-error --globoff \
            --connect-timeout 10 --max-time 30 \
            --output "$temporary" "https://icon.horse/icon/$domain"
        if test -s "$temporary"
            command mv -f -- "$temporary" "$icon_path"; or return 1
            set icon "$icon_path"
        end
    end
    command rm -f -- "$temporary"
    if test "$icon" = "$fallback_icon"
        printf 'Warning: icon download failed; using the system icon %s.\n' "$fallback_icon" >&2
    end

    # Exec uses desktop-entry escaping, not shell quoting.
    set -l exec_args
    for argument in $launcher "--user-data-dir=$profile" "--app=$url"
        set argument (string replace -a '\\' '\\\\' -- "$argument")
        set argument (string replace -a '"' '\\"' -- "$argument")
        set argument (string replace -a '$' '\\$' -- "$argument")
        set argument (string replace -a '`' '\\`' -- "$argument")
        set argument (string replace -a '%' '%%' -- "$argument")
        set -a exec_args "\"$argument\""
    end
    set -l exec_line (string join ' ' -- $exec_args)

    # Escape desktop-entry values while preserving the original display name.
    set -l values
    for value in "$name" "$icon" "$exec_line"
        set value (string replace -a '\\' '\\\\' -- "$value")
        set value (string replace -a \n '\n' -- "$value")
        set value (string replace -a \r '\r' -- "$value")
        set value (string replace -a \t '\t' -- "$value")
        set -a values "$value"
    end
    set values[1] (string replace -a ' ' '\s' -- "$values[1]")

    set -l desktop_tmp (command mktemp "$applications/.webapp-$slug.XXXXXX"); or return 1
    if not printf '%s\n' \
            '[Desktop Entry]' \
            'Type=Application' \
            "Name=$values[1]" \
            "Exec=$values[3]" \
            "Icon=$values[2]" \
            'Terminal=false' \
            'Categories=Network;WebBrowser;' \
            "StartupWMClass=chrome-$slug" > "$desktop_tmp"
        command rm -f -- "$desktop_tmp"
        return 1
    end
    command chmod 644 -- "$desktop_tmp"; or return 1
    command mv -f -- "$desktop_tmp" "$desktop"; or return 1

    if command -q update-desktop-database
        command update-desktop-database "$applications"
        or printf 'Warning: desktop database update failed.\n' >&2
    end

    printf 'Web app created: %s\nLauncher: %s\nIcon: %s\nIsolated profile: %s (created on first launch)\n' \
        "$name" "$desktop" "$icon" "$profile"
end
