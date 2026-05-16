# Pique

<img src="Pique/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" alt="Pique icon" width="128" height="128" />

A macOS Quick Look extension for syntax-highlighted previews of configuration files and scripts.

Select a file in Finder, press Space, and get a formatted preview with proper syntax highlighting to make your MacAdmin life easier — no need to open a text editor to glance at a config file.

## Supported File Types

| Format | Extensions | |
|---|---|---|
| JSON | `.json` | |
| YAML | `.yaml`, `.yml` | |
| Mobileconfig / Plist | `.mobileconfig`, `.plist` | |
| XML | `.xml` | |
| Shell | `.sh`, `.bash`, `.zsh`, `.ksh`, `.dash`, `.rc`, `.command` | |
| Markdown | `.md`, `.markdown` | ✨ New |
| PowerShell | `.ps1`, `.psm1`, `.psd1` | |
| TOML | `.toml`, `.lock` | |
| Python | `.py`, `.pyw`, `.pyi` | ✨ New |
| JavaScript | `.js`, `.jsx`, `.mjs`, `.cjs` | ✨ New |
| TypeScript | `.ts`, `.tsx`, `.d.ts` | ✨ New |
| HCL / Terraform | `.tf`, `.tfvars`, `.hcl` | ✨ New |
| Go | `.go` | ✨ New |
| Rust | `.rs` | ✨ New |
| Ruby | `.rb`, `.gemspec` | ✨ New |
| NDJSON / JSON Lines | `.ndjson`, `.jsonl` | ✨ New |
| AutoPkg Recipe | `.recipe` | ✨ New |
| Apple VPP / Apps and Books Token | `.vpptoken` | ✨ New |
| AsciiDoc | `.adoc` | ✨ New |

Rows marked ✨ New were added after the initial release.

Mobileconfig and plist files get a special HIG-inspired rendering with profile metadata, payload details, and formatted key-value pairs.

YAML files with embedded SQL in `query:` values (common in osquery/Fleet configurations) automatically highlight the SQL syntax.

## Requirements

macOS 26.0 or later.

## Installation

Download and run the pkg installer from [Releases](../../releases).

Optionally, you can build from source with Xcode:

```sh
xcodebuild -project Pique.xcodeproj -scheme Pique -config Release
```

## Enabling the Extension

On macOS 26, Quick Look extensions must be explicitly allowed. When you first launch Pique, you will see a notification:

<img src="images/quicklook-extension-enable.png" alt="Quick Look Previewer Extension Added notification" width="350" />

Go to **System Settings > Login Items & Extensions > Quick Look Extensions** and enable **Pique**.

## Appearance Settings

Open the **Pique** app and click the gear icon (⚙️) in the bottom-right corner to open **Appearance Settings**.

- **Per-Format Appearance** — every format defaults to **System** (follows the macOS appearance). You can override an individual format to always render **Light** or **Dark** — for example, keep shell scripts dark while Markdown stays light.
- **Show Line Numbers** — a global toggle that adds line numbers to code previews.

Settings are stored in a shared App Group (`group.io.macadmins.pique.apps`), so the Quick Look extension picks up your changes on the next preview.

## Renewing the Quick Look Cache

macOS caches Quick Look previews and the list of registered generators. After installing or updating Pique — or if a supported file still shows the plain-text preview — renew the cache:

```sh
# Reset the thumbnail/preview cache and reload all generators
qlmanage -r cache
qlmanage -r

# Restart Finder so it picks up the refreshed previews
killall Finder
```

To confirm Pique is registered, list the active generators and look for `io.macadmins.pique`:

```sh
qlmanage -m | grep -i pique
```

If previews still don't update, log out and back in (or reboot) so macOS reloads the extension.

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for build and release notes, including how to prepare provisioning profiles for the GitHub Actions release workflow.

## License

Copyright 2026 Declarative IT GmbH

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

> <http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
