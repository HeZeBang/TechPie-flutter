# Linux packages

`linux-release.yml` compiles once on Ubuntu 24.04 and produces:

- `TechPie-<release name>-linux-x86-64.tar.gz`
- `TechPie-<release name>-linux-x86-64.AppImage`
- `TechPie-<release name>-linux-x86-64.flatpak`
- `SHA256SUMS-linux.txt`

The tarball and AppImage contain the same Flutter bundle, including desktop widgets
when present. Flatpak packages the main application using GNOME 51; see
[Flatpak packaging](flatpak-packaging.md) for its runtime, installation and sandbox
permissions. The release job attaches all formats to the draft before the main workflow
publishes it. Versions and tags continue to come from the existing release plan.

## AppImage

The image contains Flutter, its plugins, application data and optional widgets.
It uses the host GTK 3, WebKitGTK 4.1, libsecret, json-glib and OpenGL libraries.
It targets the Ubuntu 24.04 library baseline and newer systems providing those
libraries; it is not a self-contained browser runtime. On Ubuntu:

```sh
sudo apt install libgtk-3-0 libwebkit2gtk-4.1-0 libsecret-1-0 libjson-glib-1.0-0 libegl1 libgl1
chmod +x TechPie-<version>-linux-x86-64.AppImage
./TechPie-<version>-linux-x86-64.AppImage
```

Where FUSE is unavailable, run with `APPIMAGE_EXTRACT_AND_RUN=1`.
`build-appimage.sh` uses appimagetool 1.9.1 and a fixed type2-runtime asset ID;
both downloads have pinned SHA-256 values. It preserves command-line arguments,
including `techpie://` links. A desktop integration tool can register the included
launcher; running the AppImage alone does not install a desktop entry.

To package an existing bundle locally:

```sh
scripts/build-appimage.sh build/linux/x64/release/bundle 1.0.4 build/packages
```

Optional widgets can be copied out with `--appimage-extract`; run their installer
with `--app /absolute/path/to/TechPie-<version>-linux-x86-64.AppImage` so the
installed widget launches the persistent image rather than its temporary mount.

## AUR: techpie-bin

After a stable GitHub release is published, `release.yml` calls
`aur-release.yml`. It downloads the Linux tarball, generates `PKGBUILD` and the
desktop entry, then builds an Arch package and `.SRCINFO` in an Arch Linux
container. The recipe files and `.pkg.tar.zst` are separate workflow artifacts.
Candidates are excluded. `pkgver` is `X.Y.Z`; `pkgrel` is the release's global
build number, so another build of the same version upgrades correctly.

The package installs the complete bundle in `/opt/techpie`, a launcher in
`/usr/bin/techpie`, and the icon and desktop entry under `/usr/share`. Optional
widget installation remains a per-user action. MIT metadata follows the License
section of the upstream README, which is included in the package.

The AUR push job is disabled until the repository owner configures:

| Setting | Kind | Value |
| --- | --- | --- |
| `AUR_PUBLISH_ENABLED` | Actions variable | `true` |
| `AUR_SSH_PRIVATE_KEY` | Actions secret | Dedicated private key registered with the AUR account |
| `AUR_KNOWN_HOSTS` | Actions variable | Verified `aur.archlinux.org` SSH host-key entries |

Create or claim `techpie-bin` with that AUR account and enable publishing in one
GitHub repository. Existing packages require maintainer/co-maintainer access.
Verify the host keys against the fingerprints published by Arch before saving
`AUR_KNOWN_HOSTS`. The workflow uses strict host-key verification and pushes only
`PKGBUILD`, `.SRCINFO` and the desktop file to the AUR `master` branch.

Only the latest stable GitHub release can update AUR. AUR failure does not undo
the already-published GitHub release. Run **AUR Release** manually to retry:
provide a stable tag and leave **publish** off to generate artifacts, or turn it
on after the above settings are ready. First run the artifact-only path and
inspect/install its Arch package before enabling automatic pushes.

Release tags used by these workflows must include the packaging scripts. Older
tags from before this change keep their original release process.

## Checks

On Arch Linux with `base-devel`, `python` and `desktop-file-utils`:

```sh
scripts/check-linux-packaging.sh
```

This builds a small fixture, launches its actual AppImage without FUSE, verifies
argument forwarding, rejects candidate AUR releases, and builds a real Arch
package to check its installed paths. `linux-packaging-check.yml` runs the same
checks when packaging files change.

References: [AppDir specification](https://docs.appimage.org/reference/appdir.html),
[AUR submission guidelines](https://wiki.archlinux.org/title/AUR_submission_guidelines),
[GitHub workflow scope](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps).
