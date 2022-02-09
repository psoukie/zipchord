# ZipChord Keyboard

_ZipChord_ is a customizable hybrid keyboard input method for Windows that augments regular typing with chorded entry. An article [Type Faster and More Comfortably with ZipChord](https://psoukenik.medium.com/type-faster-and-more-comfortably-with-zipchord-fdee71b28392?sk=27b82576a598d900d52ca1f65504cf8f) discusses why this might be useful.  

## Installation

Download and save the executable **zipchord.exe** of the latest [release](https://github.com/psoukie/zipchord/releases) in a folder where you have read and write access, and run it. (Optionally, download a dictionary from the dictionaries folder to use as a starting point.)

(Note that _ZipChord_ has not been ported to MacOS because of its dependency on AutoHotKey.)

## Using ZipChord

Type normally using individual keystrokes in combination with predefined chords of several keys pressed at the same time to enter whole words. _ZipChord_ will use smart spaces and capitalization to add (or remove) spaces as needed to separate words whether they were typed using individual strokes or chords and to capitalize words as selected.

To define a new chord, select the word you want to define a chord for, and **press and hold Ctrl-C** until a dialog box appears. Next, type the individual keys (without pressing Shift or any function keys) and click OK. If the selected text is already in the dictionary, _ZipChord_ will remind you of its chord.

## Menu Options

To open the menu, click the _ZipChord_ icon in the Windows tray, or press and hold **Ctrl-Shift-C**.

The dictionary group shows the current dictionary and the number of chords it contains. You can select a different dictionary file, open it for direct editing, and reload the dictionary if changes were made to the file.

The chord recognition option allows you to change the sensitivity of the chord recognition (the delay before multiple keys held down are treated as a chord) or temporarily disable the chord recognition. It also has three options for smart punctuation:

* Off: Spaces and capitalization are never adjusted around punctuation.
* For chords: Spaces are added and words are capitalized only when punctuation precedes or follows chorded entry.
* All input: Spaces are always added after punctuation and words are capitalized even for regular typing.

## Chord Dictionary

_ZipChord_ uses a separate text file with a dictionary of chords and the full words. _ZipChord_ will remember the last used dictionary. (Note: When you run _ZipChord_ for the first time or the dictionary isn't available, it will either open a chord*.txt file in its working folder or create a new chord.txt.)

Chord dictionaries are text files which define each chord on a separate line. Each entry is defined as follows:

* Lowercase keys that form the chord (the key order does not matter, space bar is represented by a single space)
* A single Tab character (note that spaces cannot be used instead of tabulator)
* The word that the chord produces. (Lowercase unless it is a proper name.)

Blank lines and lines without a tab are ignored and can be used as comments.

_ZipChord_ will notify you if two words are attempting to use the same chord, such as in the following example where two words are using the chord W N.
```
wn   win
ths  this
nw   new
```
Note that if you edit the dictionary file directly in a text editor, you need to click the Reload button from the _ZipChord_ menu for the changes to be loaded.

## Special Characters

Chord can only consist of alphanumerical keys, including space bar (simply type a space in the chord, e.g. "` w`"), number keys, and keys for comma, semicolon etc. (,./;'[]-=\\). Note that Shift, Control, Tab and other function keys cannot be used in a chord.

The words entered using a chord can include the following special features:

* **Suffixes**: To define suffixes that can be entered using a chord and joined to the last word, start the word definition with ~. Example: `;g  ~ing` (pressing **;** and **G** together will add "ing" to the last word). Note that `~~ing` would also remove the last character of the preceding word.
* **Prefixes**: For prefixes, place the `~` at the end of the prefix (such as `pre~`). This will ensure there will be no space after the chord.
* **Special keys**: Other keys can be entered using expressions in curly braces: {Left}, {Right}, {Up}, {Down} for cursor, {Tab} and {Enter} can all be used.

## Feedback

If you have any feedback, feature requests, or encounter a bug, you can contact me on Twitter at [@pavel_soukenik](https://twitter.com/pavel_soukenik).
