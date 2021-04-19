# zipchord
ZipChord is a customizable hybrid keyboard input method that augments regular typing with chorded entry.

## Installation
1. Download and save the executable of the latest [release](https://github.com/psoukie/zipchord/releases) in a folder where you have read and write access.
2. Optionally, download a dictionary from the dictionaries folder and save it in the same folder to use as a starting point.
3. Run the zipchord.exe

## Chord Dictionaries
ZipChord uses a separate text file with a dictionary of chords and the full words. ZipChord will remember the last used dictionary. (Note: When you run ZipChord for the first time or the dictionary isn't available, it will either open a chord*.txt file in its working folder or will create a new chord.txt.)

## Using ZipChord
Type normally using individual keystrokes and enter whole words by briefly pressing and releasing pre-defined chords (combinations of several keys). ZipChord will add (or remove) spaces as needed to separate words and punctuation, whether they were typed using individual strokes or chords. 

To define a new chord, select the word you want to define, and press and hold Ctrl-C until a dialog box appears. Next, type the individual keys (without pressing Shift or any function keys) and press OK.

To open the menu, click the ZipChord icon in the Windows tray, or press and hold Ctrl-Shift-C. From the menu, you can pause the chord recognition, select a different dictionary file or open it for editing, and change the sensitivity of the chord recognition (the delay that triggers a chord).

## Chord Dictionary
Chord dictionaries are text files which define each chord on a separate line. Each entry includes the typed chord (lowercase keys that form the chord), tabulator, and the word represented by the chord. Blank lines and lines without a tab are ignored.

ZipChord will notify you if two words are attempting to use the same chord, such as in the following example where two words are using the chord W N.
```
wn   win
ths  this
nw   new
```

## Special Characters
* **Space bar**: It is possible to use the space bar as part of the chord definition. Simply start the chord with a space.
* **Suffixes**: To define suffixes that can be entered using a chord and joined to the last word, start the word definition with ~. Example: `;g  ~ing` (pressing ; and G together will add "ing" to the last word)
