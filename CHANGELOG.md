# ZipChord Changelog

## ZipChord 2.6.0

**New Features**

- Expansion of shortcuts (chords and shorthands) now capitalizes the expanded text when Caps Lock is on.


## ZipChord 2.5.0

**New Features**

- Added an automated update check. (This check can be turned off on the About tab).
- Added an option to hide the ZipChord window when the app starts (#237). Thanks to @ollyisonit for the idea and initial code!
- Renamed the Hints tab to Display to better match its options.

**Improvements and Fixes**

- Improved how chords and shorthands are expanded into full text.
- ZipChord now handles Ctrl+Backspace gracefully. (Fixes [#235](https://github.com/psoukie/zipchord/issues/235))

**Note**

Note that the Output Delay setting (which is useful for apps or editors where replacements did not work well) is now applied after every simulated keystroke. This change makes replacements even more reliable, but you may need to adjust the delay in the Output setting.

## ZipChord 2.4.1

**Fixes**

This release focuses on mainly cosmetic issues that could sometimes trigger warnings or errors: 
 
- Repeated (or longer) press of the keyboard hotkey for adding a ZipChord shortcut no longer leads to error but re-focuses the Add Shortcut window instead (#214)
- Starting ZipChord after exiting it in a paused mode correctly indicates its status as active (#204)
- Removed the spurious warning message about X number of hotkeys received within an interval (#216)


## ZipChord 2.4

**New Features**

This release includes the command line features for storing, loading, and automatically switching configurations between windows.

See [Configuration and Automated Switching](https://github.com/psoukie/zipchord/wiki/Configurations-and-automated-switching) in the Wiki for details.

**Fixes**

- Fixes a bug where installer was not working correctly if the user was logged in with elevated Admin rights (#206)
- Fixes a regression (now with a test case added) where shorthand entries starting with prefix (`~`) did not work correctly (#205)


## ZipChord 2.4 Release Candidate

**New Features**

This version implements several command line options for storing, loading, and automatically switching configurations based on the active window, as suggested by @lmendez5.

- Implements saving and restoring settings and locales into configuration files from command line (#45) 
- Allows automatic switching between configurations based on window titles (#31)
- Provides command line access to pausing and resuming ZipChord and for reverting to normal operation

See [Configuration and Automated Switching](https://github.com/psoukie/zipchord/wiki/Configurations-and-automated-switching) in the Wiki for details. I'm open to tweaking the functionality based on feedback.


## ZipChord 2.3.1

**Fixes**

- This fixes a bug where typing a shorthand in a way that can be considered a chord could hang the app in some situations (#200)


## ZipChord 2.3

**New Features**

- Added typing efficiency showing percentages and graphical representation of chords, shorthands, and manual typing over the last 100 words. (#113) (See [documentation](https://github.com/psoukie/zipchord/wiki/Main-Window#hints))
- Chords can now also be capitalized by pressing and releasing Shift before using the chord (#185)
- Pressing Shift also enables shorthand recognition (without capitalizing the word) after moving the caret
- Backspace can now be used to correct typing of a shorthand, and it will be correctly recognized (#159)

**Improvements and Fixes**

- Fixed regression bug that prevented adding chord prefixes and suffixes to shorthands (#195)
- Improved installation and first run experience
- Under the hood improvements in handling of UI and settings


## ZipChord 2.2.2

**Improvements and Fixes**

- Adds a better mechanism for removing smart spaces around numbers, for example in `2.2`, `1,000`, or ` .5` (see #186 for details.)
- This also fixes bug #189 where attempting to type "_text.)_" led to incorrect output
- Fixes a bug which caused hints for shortcuts not to be shown (#188)

**Note:**

This version replaces the attempted workaround for smart spaces between full stops and numbers that was introduced briefly in version 2.2.1, such as:

```
. 0	.0
. 1	.1
```

If you added these entries to your dictionary, you should remove them.


## ZipChord 2.2.1

**Fixes and Improvements**

- Words with capital letters after the first character (_USD_, _PvP_, _posX_) now do not trigger shorthands (based on #123)
- Default dictionaries now avoid unwanted smart spaces after punctuation* (See #127 and #133 for details)
- Fixes a bug in expanding infix chords (#182)
- Fixes a regression in version 2.2 for a bug which did not have a test case (#169)
- Under the hood improvements, including in testing console and in mechanism for smart space followed by a manual space


## ZipChord 2.2

**New Features**

- This version implements the 'chained chords' feature (#155) (referred to as compound chords previously)

**Improvements**

- Fixes bugs in the Test Console.

See [chained chords](https://github.com/psoukie/zipchord/wiki/Shortcuts#chained-chords) in the documentation for information on how to use this feature.


## ZipChord 2.1.3

**Improvements and Fixes**

This version has minor fixes and improvements:

- You can now use Ctrl-Backspace in the Add Shortcut dialog box (#172)
- When "Restrict chords while typing" and "Delete mistyped words" are both enabled and a non-existing chord is registered while typing a word, this input is now left alone. (Because it is safe to assume it was intended as normal typing).
- Fixed a duplicate hotkey accelerators in the main ZipChord window which was accidentally introduced during previous UI redesign (#171).


## ZipChord 2.1.2

**Changes and Improvements**

- You can now use a chord immediately after a mistyped chord is deleted (#168). This fixes a bug that was blocking chords when both "Delete mistyped chords" and "Restrict chords while typing" were active.
- A smart space is no longer inserted when you move the caret to a new location and type a punctuation (#169).


## ZipChord 2.1.1

**Changes and Improvements**

- Added an option during the first run to download starting English dictionaries and place them into a working folder under My Documents.
- Under the hood: Switched app configuration settings from Windows Registry to an INI file for easier handling by third party installers.

**Notes**

- Because of the changes, the app will start with default settings on the first run.
- These changes bring the experience of using the standalone executable closer to that of using the installer.


## ZipChord 2.1

* ZipChord 2.1 comes with optional install and uninstall features (see notes on installation below)
* Changed the Pause checkbox to a button
* The "New" locale button now correctly checks for existing locale with the same name
* Cosmetic fixes:
   * App Shortcuts window default to OK button and temporarily disables shortcuts to prevent accidental changes
   * The Tip window shows currently selected shortcuts
   * License file is correctly installed
* Test Console improvements (can now be opened after running debugging from About tab, and other improvements)

### Installation

You can either download the **zipchord-exe-2.1.0.zip**, save in a preferred location and run (same as previous releases), or download and use the installer by downloading **zipchord-install-2.1.0.zip** or **zipchord-install.exe**. (With the Beta 2 version, it took Microsoft a few days to whitelist the installation zip file as safe.) The installer allows you to choose to create Start menu shortcuts, dictionary folder and other options, and also creates entries and shortcuts for uninstallation.

### Note on the Developer version

The standard and "Developer" versions have now merged but the Developer features are not enabled by default. To use the key visualizer or test console features, select the option "Create a Developer version shortcut in Start menu" during installation and then use that version when needed, or run the program using the "zipchord dev" command.


## ZipChord 2.1 Beta 2

* Added install and uninstall functionality
* Changed the Pause checkbox to a button
* The "New" locale button now correctly checks for existing locale with the same name
* Cosmetic fixes:
   * App Shortcuts window default to OK button and temporarily disables shortcuts to prevent accidental changes
   * The Tip window shows currently selected shortcuts
   * License file is correctly installed
* Test Console improvements (can now be opened after running debugging from About tab, and other improvements)

### Installation

You can either download the **zipchord-exe-2.1.0-beta.2.zip**, save in a preferred location and run (same as previous releases), or download and use the installer by downloading **zipchord-install-2.1.0-beta.2.zip**.

Update: I also included the **zipchord-install.exe** because Windows Defender considers the Zip unsafe. (I have submitted this to Microsoft and am hoping they can fix this soon. In the meantime, download either the uncompressed zipchord-install.exe file which should not be blocked if you want to use the installer.

The installer allows you to choose to create Start menu shortcuts, dictionary folder and other options, and also creates entries and shortcuts for uninstallation.

### Note on the Developer version

The standard and "Developer" versions have now merged but the Developer features are not enabled by default. (The separation in Beta 1 was not accomplishing brining the benefits I was aiming for.) If you want to use the Developer features, select the option "Create a Developer version shortcut in Start menu" during installation and then run that version when you want to, or run the program with the "zipchord dev" command.

I tested the installation and uninstallation in different combinations (with Admin and non-Admin accounts) on Windows 10 and Windows 11. If you experience issues with the installation process, please let me know.


## ZipChord 2.1 Beta

## New Features

- **Pause ZipChord** feature in the main menu and the app's Windows tray menu
- **Customize app shortcuts** for shortcuts to Open ZipChord, Add Shortcut, Pause/Resume ZipChord and Quit
- **Context-sensitive help** by pressing F1 in any ZipChord window/tab

### Changes

* The default keyboard shortcut for opening ZipChord's window is now by holding Ctrl+Shift+Z
* ZipChord 2.1 (and future versions) are released are under [BSD 3-Clause license](https://github.com/psoukie/zipchord/blob/main/LICENSE)
* ZipChord 2.1 (and future versions) is distributed with two compiled executables, normal and an extended, "Developer" version

### ZipChord Developer version

These additional features are included in the "zipchord-dev" version of ZipChord and accessible through ZipChord's tray icon menu.

- Key Visualizer window (the same that was used for this [screen recording](https://github.com/psoukie/zipchord/wiki/How-to-use-ZipChord))
- ZipChord Test Automation Console - use 'help' in the console to see available commands or 'help command' to learn more
- "Log this session (debugging)" option on the About tab of main ZipChord window to create a local debugging file. 

### Privacy Note

ZipChord does not send or share any information over the network or internet, and the standard version is unable to store any information about your typing. The Developer version _can_ save local files with information about input and output but only if you explicitly start such recording using the "Log this session" checkbox or in the automation console.


## ZipChord 2.0.1

**Improvements and Fixes**
- Improves Hints OSD when using multiple monitors to display on the active monitor (#134)
- Consolidates the notice about keys not matching current keyboard layout into one message (#137)
- Removes debugging features (debugging will be available in a separate version)


## ZipChord 2.0

ZipChord 2.0 includes several new features:

* Separate "shorthand" dictionary for expanding regularly typed text
* OSD hints with reminders for shortcuts in your dictionaries
* New interface for defining new shortcuts
* [New documentation](https://github.com/psoukie/zipchord/wiki) on Wiki

And many additional improvements described in the preview releases listed on the [Releases](https://github.com/psoukie/zipchord/releases) page.

This version has minor improvements compared to Release Candidate 2:

* Adding a shortcut (hold Ctrl+C) now does not require text to be selected first
* The executable version is now provided as a zip archive (under Assets)
* Cosmetic improvements in user interface of the main window and tray icon menu
* Special keys can now be used in definitions of shorthands


## Older Releases

For earlier release history, see the GitHub Releases pages: https://github.com/psoukie/zipchord/releases