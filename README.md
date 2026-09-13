<p align="center">
  <img src="assets/zipchord_logo.svg" width="240" alt="ZipChord logo" />
</p>

<h1 align="center">ZipChord</h1>

[Download](https://github.com/psoukie/zipchord/releases/latest) · [Documentation](https://github.com/psoukie/zipchord/wiki) · [Discussions](https://github.com/psoukie/zipchord/discussions)

[![Latest release](https://img.shields.io/github/v/release/psoukie/zipchord)](https://github.com/psoukie/zipchord/releases/latest)
[![License: BSD 3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue)](LICENSE)

<img align="right" src="https://raw.githubusercontent.com/wiki/psoukie/zipchord/images/zipchord-demo-border.gif" width="400" alt="ZipChord demo" />

ZipChord is a Windows app for hybrid typing: it lets you mix normal typing, simultaneous chords, and typed shorthands in the same flow.

Instead of learning full stenography, you can start with just a few shortcuts for the most common words and phrases. ZipChord is built around the idea that a small number of high-frequency shortcuts can speed up a large share of everyday typing.

## Why ZipChord?

- Keep using your normal keyboard and regular typing habits
- Add simultaneous chords for frequent words
- Expand typed abbreviations into longer text with shorthands
- Learn gradually with real-time hints and reminders
- Keep everything local and private on your computer

## Features

- Simultaneous chord recognition (also known as chorded entry or chording)
- Sequential shorthands that expand typed abbreviations to full words or phrases
- Customizable dictionaries for chords and shorthands
- Real-time hints in an on-screen display or tooltips
- Smart spaces and automatic capitalization around shortcuts and punctuation
- Two chord-detection modes: minimum held duration or relative overlap of keys
- Automatic switching of key mapping and dictionaries with the active Windows keyboard layout
- Native UI and command menu for common actions and assigning shortcuts

## Examples

With the bundled English QWERTY chord and English shorthand dictionaries:

| Input | Output |
| --- | --- |
| Press `S` + `D` simultaneously | should |
| Type `adrs`, then press Space | address |

Use hints while typing to discover or remember available shortcuts. Smart capitalization adjusts the output to its context.

## Quick Start

**Requires Windows.**

1. Download **zipchord-install-_version_.zip** from the [latest release](https://github.com/psoukie/zipchord/releases/latest).
2. Extract the archive and run the included installer.
3. Follow [How to use ZipChord](https://github.com/psoukie/zipchord/wiki/How-to-use-ZipChord) to try your first chords and shorthands.

For installation options that do not use the installer, see the [Installation guide](https://github.com/psoukie/zipchord/wiki/Installation).

## Documentation

Official [documentation](https://github.com/psoukie/zipchord/wiki) is available under the **Wiki** tab.

## Privacy

ZipChord adheres to strict privacy and security principles. It does not send your typed content or configuration data anywhere. See more [privacy details](https://github.com/psoukie/zipchord/wiki/Privacy) in the Wiki.

## Development

ZipChord was first released in 2021. This repository contains two development tracks:

- **ZipChord 2.x** is the supported Windows application, written in [AutoHotkey v1](https://www.autohotkey.com/) under [`source/`](source/), with an optional [Odin](https://odin-lang.org/) dictionary-acceleration library under [`native/zipchord-lib/`](native/zipchord-lib/).
- **ZipChord 0** is an in-progress standalone, cross-platform implementation in Odin under [`native/zipchord/`](native/zipchord/). It initially targets Windows, with support for macOS and Linux as a longer-term goal. It is not yet a replacement for ZipChord 2.x.

Design and implementation are done by the maintainer, with generative AI used for code review, troubleshooting, technical recommendations, and documentation.

## Feedback

If you have any questions, feedback, or suggestions, please write a note in the [Discussions](https://github.com/psoukie/zipchord/discussions). You can also report a bug if you run across anything that seems broken or create a feature suggestion under [Issues](https://github.com/psoukie/zipchord/issues).

## License

ZipChord is released under the [BSD 3-Clause License](LICENSE).
