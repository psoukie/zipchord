# Security Policy

This policy explains which versions of ZipChord receive security updates and how to report a security concern. For details about how ZipChord handles typed text and internet access, see the [Privacy page](https://github.com/psoukie/zipchord/wiki/Privacy).

## Supported versions

Only the latest ZipChord release receives security updates.

| Version | Supported |
| :--- |:---:|
| Latest release | Yes |
| Older releases | No |

When possible, check whether the problem affects the latest release or the latest code on `main` before reporting it.

## Reporting a security concern

Please [report security concerns privately through GitHub](https://github.com/psoukie/zipchord/security/advisories/new). Do not open a public issue if the report could put users at risk.

Please include:

- What the problem is and what harm it could cause
- Steps that reproduce it
- The affected ZipChord version or commit
- Your OS version and how you installed or ran ZipChord
- Any relevant settings, logs, or other information

I aim to acknowledge a report within five days. I will investigate it, ask for more information if needed, and explain whether I consider it a security issue. If it is accepted, I will work with the reporter to fix it and agree on when to make it public. The time needed will depend on the problem.

## What to report

Please report any problem that could cause ZipChord to:

- Save typed text when it should not
- Send typed text over a network
- Run code or access files in a way the user did not request
- Gain more access to the computer than the user approved
- Install or load an untrusted update or file
- Handle a dictionary or settings file in an unsafe or unexpected way

This policy covers the official release files, installer, source code, included library, and included AutoHotkey runtime.

## Expected behavior

ZipChord is a keyboard automation app. To work, it must monitor keyboard input and send text or key presses to the active app. This expected behavior is not by itself a security problem.

ZipChord dictionaries can include commands for special keys such as Enter, Backspace, and the arrow keys. Use dictionaries only from sources you trust.

The following are not considered security issues:

- Expected text or key presses produced from the user’s typing, based on dictionaries and settings they selected
- Problems that require someone to already have access to replace ZipChord, its library, settings, or dictionary files, unless ZipChord provided that access
- Problems found only in a modified or unofficial build
- An antivirus warning without evidence of unsafe behavior

## AutoHotkey

Official compiled releases include the AutoHotkey runtime needed by ZipChord. Problems in AutoHotkey itself should be reported to the AutoHotkey project. Please also report them here if they affect an official ZipChord release, so I can assess the effect and any mitigation available within ZipChord.
