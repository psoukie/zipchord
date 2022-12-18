# ZipChord Keyboard

_ZipChord_ is a customizable hybrid keyboard input method for Windows that allows you to seamlessly **combine regular typing with chorded entry**. Chords allow you to type whole words by pressing a combination of keys simultaneously. That's what stenographers do and what makes them so fast.

Thanks to Zipf's law, even if we used simple chords for only a few dozen words, it would still accelerate a huge amount of our typing. For example, 40% of the text of _The Lord of the Rings_ consists of only 32 words. Unfortunately, I could not find any tool that could reliably detect keyboard shortcuts of more than two keys, and tools dedicated to stenotyping (such as [Plover](http://www.openstenoproject.org/plover/)) by design do not work for regular typing.

_ZipChord_ fills this gap and lets you type faster and more comfortably by allowing you to use chords for frequent words (or phrases) together with regular typing.

For more details on why combining typing and chords is useful, see [ZipChord: Hybrid Chorded Keyboard](https://pavelsoukenik.com/zipchord-hybrid-chorded-keyboard).  

## Installation

Download and save the executable **zipchord.exe** of the [latest release](https://github.com/psoukie/zipchord/releases) in a folder where you have read and write access, and run it.

_ZipChord_ allows you to define your own chords for your own words, but you can download a chord dictionary from the [dictionaries](https://github.com/psoukie/zipchord/tree/main/dictionaries) folder to use as a starting point.

Note that _ZipChord_ only works on Windows because of its dependency on AutoHotKey.

### Defining New Chords

To define a new chord, select the word or text you want to automate as a chord and **press and hold Ctrl-C** until a dialog box appears. Next, type the individual keys (without pressing Shift or any function keys) and click OK.

Note that if the selected text is already defined in the chord dictionary, holding Ctrl-C will remind you of its chord.

## Typing with ZipChord

Type normally using individual keystrokes in combination with predefined chords. Chords are several keys pressed at the same time which type out whole words (or prefixes and suffixes). _ZipChord_ uses smart spaces and capitalization to add (or remove) spaces as needed to separate words, whether they were typed using individual strokes or chords, and to capitalize words.

To use the chord, press the keys that make up the chord simultaneously and release them. You can configure the sensitivity of chord recognition and also the automatic behavior for spaces and capitalization.

## Menu Options

To open the menu, click the _ZipChord_ icon in the Windows tray or press and hold **Ctrl-Shift-C** until the menu appears.

### Dictionary

The dictionary tab shows the currently loaded chord dictionary and the number of chords it contains. You can select a different dictionary file using the **Open** button, edit its chords directly in default text editor (**Edit**), and **Reload** the dictionary when you make changes to the chord file directly in an editor.

You can download a dictionary from the [dictionaries](https://github.com/psoukie/zipchord/tree/main/dictionaries) folder to use as a starting point. 

**Notes:**
* See [below](#chord-dictionary) for more details about the chord dictionary file and advanced features.
* When you add chords by selecting text and pressing and holding Ctrl-C, the new chord is added automatically, and you do not need to open the menu to edit or reload the dictionary.  

### Chord detection

This tab allows you to adjust the sensitivity and rules for the chord recognition. The basic idea behind the chords is that there needs to be a short minimum time that the keys are held together before being released (which is set by the "detection delay").

**Detection delay:** Depending on your regular typing, you might be holding two or more keys pressed at the same time for longer than the threshold that triggers the chord recognition. This can result in some intended key presses in your regular typing being misinterpreted as chords. In that case, you can increase the number of milliseconds under detection delay.

**Restrict chords while typing:** When this option is on, the keyboard is restricted to normal typing and ignores chords, unless the chord is preceded by a space, another chord, permitted punctuation or by moving the cursor. Note that chords defined as suffixes (see below under [Special Characters](#special-characters)) will still be recognized in this mode.

**Allow Shift in chords:** When this option is not checked, Shift key behaves normally (when pressed together with a defined chord, it capitalizes the word). By checking this box, this standard functionality is replaced with the ability to define chords that use Shift as a key in the chord. (It makes Shift work like other standard keys and space bar. Use `+` to represent Shift in chords.)

**Delete mistyped chords:** This option allows you to automatically remove unrecognized chords. If you are encountering situations where your intended key presses are being deleted, either do not use this option or increase the number of milliseconds under Input delay.

### Output

This tab allows you to change the typing and chord behavior to adjust how spaces and capitalization are handled around chords and punctuation.

**Smart spaces**: The smart spaces--when enabled--ensure correct spacing around chords and punctuation. This means that spaces are added automatically if you haven't typed one manually, but the smart spaces are also dynamically removed if they are followed by punctuation or you type another space manually. Smart spaces can be enabled to be inserted as follows:
- **In front of chords**
- **After chords**
- **After punctuation**  

**Auto-capitalization** offers three options:
- **Off:** Automatic capitalization is not used. (To manually capitalize a chorded word, press Shift in parallel with the chord entry.)
- **For chords only:** Text is automatically capitalized only for words entered using chords.
- **For all input:** All text is automatically capitalized even for regular typing.

**Output delay:** In some situations, the window you are typing in might be outputting the chords with some distortions (where keystrokes are replaced incorrectly). In that case, you can try setting the Output delay to 50ms, which can solve the issue.

### Enabling and Disabling the Chords

You can temporarily disable the chord recognition by unchecking the **Use chord detection** checkbox.

## Chord Dictionary

_ZipChord_ uses a separate text file with a dictionary of chords and the full words. _ZipChord_ will remember the last used dictionary. (Note: When you run _ZipChord_ for the first time or the dictionary isn't available, it will either open a chord*.txt file in its working folder or create a new chord.txt.)

Chord dictionaries are text files which define each chord on a separate line. Each entry is defined as follows:

* Lowercase keys that form the chord (the key order does not matter, space bar is represented by a single space)
* A single Tab character (note that spaces cannot be used instead of tabulator)
* The word that the chord produces. (Lowercase unless it is a proper name.)

Blank lines and lines without a tab are ignored and can be used as comments.

_ZipChord_ will notify you if two words are attempting to use the same chord, such as in the following example where two words are using the chord **`W`** + **`N`**.
```
wn   win
ths  this
nw   new
```
Note that if you edit the dictionary file directly in a text editor, you need to click the Reload button from the _ZipChord_ menu for the changes to be loaded.

### Special Characters

Key that activate a chord can only consist of alphanumerical keys, including space bar (simply type a space in the chord, e.g. "` w`" (a space and lower-case w) to represent a **`Spacebar`**+**`W`**), number keys, and keys for comma, semicolon etc. (,./;'[]-=\\). Note that Control, Tab and other function keys cannot be used in a chord.

The Shift key can be optionally used as part of chords. If this feature is enabled ("Allow Shift in chords" on the "Chord detection" tab), use the character `+` (plus) to represent the Shift key when defining chords within the app, or directly in the dictionary file.

The words entered using a chord can include the following special features:

- **Suffixes**: To define suffixes that can be entered using a chord and joined to the last word, start the word definition with ~. Example: `;g  ~ing` (pressing **`;`** and **`G`** together will add "ing" to the last word).
- **Prefixes**: For prefixes, place the `~` at the end of the prefix (such as `pre~`). This will ensure there will be no space after the chord.

Note that chord detection works for suffixes and all chords will also be detected when they follow a chorded prefix even when the 'Restrict chords while typing' is enabled.

- **Control keys**: Other keys can be entered using expressions in curly braces: {Left}, {Right}, {Up}, {Down} to move the cursor, or {Tab}, {Backspace} and {Enter} can all be used. When using these control keys (or the character "{"), the expanded text is interpreted using AutoHotkey's modifiers and special keys.
- **Combinations**: You can combine these features for example to create a suffix that also deletes the last letter of the previous word. (In English, this can be useful to modify verbs where you need to drop the last -e. So to write the word "having" using chords, you can use a chord for "have" and then a chord for "ing" that would be expanded to `~{Backspace}ing` -- so it acts as a suffix which removes the last character.)

## Feedback

If you have any questions, feedback, or suggestions, please write a note in the [Discussions](https://github.com/psoukie/zipchord/discussions). You can also report a bug if you run across anything that seems broken or create a feature suggestion under [Issues](https://github.com/psoukie/zipchord/issues).
