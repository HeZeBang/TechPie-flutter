#!/usr/bin/env python3
"""Generate the AUR recipe for an existing stable Linux release."""
import argparse
import hashlib
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--bundle', required=True, type=Path)
    parser.add_argument('--repository', default='HeZeBang/TechPie-flutter')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    version = subprocess.check_output(
        [str(ROOT / 'scripts/release-name.sh'), args.tag], text=True,
    ).strip()
    if '-' in version or not args.tag.startswith('v'):
        parser.error('AUR accepts stable vX.Y.Z+B releases only')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repository):
        parser.error('repository must be owner/name')
    expected = f'TechPie-{version}-linux-x86-64.tar.gz'
    if args.bundle.name != expected:
        parser.error(f'expected bundle named {expected}')
    args.output.mkdir(parents=True, exist_ok=True)
    desktop = ROOT / 'packaging/linux/techpie.desktop'
    values = {
        'VERSION': version,
        'BUILD': str(int(args.tag.rsplit('+', 1)[1])),
        'TAG': args.tag,
        'REPOSITORY': args.repository,
        'BUNDLE_SHA256': sha256(args.bundle),
        'DESKTOP_SHA256': sha256(desktop),
        'ICON_SHA256': sha256(ROOT / 'assets/icon/icon.png'),
        'README_SHA256': sha256(ROOT / 'README.md'),
    }
    recipe = (ROOT / 'packaging/aur/PKGBUILD.in').read_text()
    for key, value in values.items():
        recipe = recipe.replace(f'@{key}@', value)
    (args.output / 'PKGBUILD').write_text(recipe)
    shutil.copyfile(desktop, args.output / 'techpie.desktop')
    print(f'Prepared techpie-bin {version}-{values["BUILD"]} in {args.output}')


if __name__ == '__main__':
    main()
