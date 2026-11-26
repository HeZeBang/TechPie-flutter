# Flatpak package

`linux-release.yml` also exports the existing Linux Release bundle as
`TechPie-<release name>-linux-x86-64.flatpak`, before the draft release is published.
The package uses `club.geekpie.TechPie` and the GNOME 51 runtime, which provides
GTK 3, WebKitGTK 4.1, libsecret and json-glib. No second Flutter build or SDK
installation is needed to create the package.

Install and launch a stable bundle:

```sh
flatpak install --user ./TechPie-<version>-linux-x86-64.flatpak
flatpak run club.geekpie.TechPie
```

The bundle records Flathub as the runtime source, so Flatpak can install the
required runtime. The runtime is a separate download. Stable releases use the
`stable` branch; candidates use `beta` and can be launched with
`flatpak run club.geekpie.TechPie//beta`.

The package exports its desktop entry, icon and `techpie://` handler. It grants
network, graphics, audio and keyring access. The prebuilt GTK runner keeps its
existing `com.example.techpie` D-Bus name, for which a specific ownership grant
is included. File selection uses the desktop portals; there is no blanket home
or host filesystem grant. Application data follows Flatpak's private
`~/.var/app/club.geekpie.TechPie` directories.

GNOME/KDE host widgets use the native package and its snapshot location. Their
installer is omitted from the sandboxed package; use the tarball or AUR package
for the existing host-widget workflow.

Build locally from an existing Flutter bundle:

```sh
scripts/build-flatpak.sh build/linux/x64/release/bundle 1.0.4 build/packages
```

To check the exporter, install `flatpak`, a C compiler, `desktop-file-utils` and
ImageMagick (the `convert` command),
then install `org.gnome.Platform//51` from Flathub and run:

```sh
scripts/check-flatpak-packaging.sh
```

The check installs a small generated bundle into a temporary user installation
and runs it inside the runtime. It checks the beta branch, argument forwarding,
exported launcher and permission metadata. `flatpak-packaging-check.yml` runs
this check independently of the AppImage/AUR checks.

References: [single-file bundles](https://docs.flatpak.org/en/latest/single-file-bundles.html),
[sandbox permissions](https://docs.flatpak.org/en/latest/sandbox-permissions.html).
