# Channel Mapper - AHK v2 GUI

A GUI application for mapping channels from a Chrome-based channel selector to virtual channel assignments.

## Files

- `ChannelMapper.ahk` - Main script (requires UIA-v2 library)
- `ChannelMapper_Standalone.ahk` - Standalone version with built-in UIA (no external library needed)
- `ChannelSetIO.ahk` - Save/Load functionality (included by main scripts)
- `ChannelAlias.ahk` - Config editor and alias matching (included by main scripts)
- `ChannelSets.ini` - Configuration file for the 60 channel sets
- `ChannelSets_Example.ini` - Example configuration with sample data

## Requirements

- AutoHotkey v2.0+
- Windows 10/11
- Chrome browser with the channel selector page open

### For ChannelMapper.ahk (recommended)
- Download the [UIA-v2 library](https://github.com/Descolada/UIA-v2)
- Place `UIA.ahk` in your AutoHotkey `Lib` folder or in the same directory as the script

### For ChannelMapper_Standalone.ahk
- No additional libraries required

## Usage

1. **Configure the INI file**: Use **Edit Config** in the app, or edit `ChannelSets.ini`, to set the name, virtual channel, and aliases for each of the 60 sets:
   ```ini
   [Set1]
   Name=ESPN
   VirtualChannel=101
   Aliases=ESPN HD|ESPN-E
   ```
   `Name` is the label on the set and is always treated as an alias. `Aliases` lists other names that channel may use, separated by `|`.

2. **Open Chrome**: Navigate to the page with the `channel_selector` element

3. **Run the script**: Double-click `ChannelMapper.ahk` or `ChannelMapper_Standalone.ahk`

4. **Load channels**: Click the "Load" button to scan Chrome for channels

5. **Assign channels**:
   - Check (tick) a channel in the ListView (only one can be checked at a time)
   - Click the arrow button (→) next to any set to assign that channel
   - The channel name and program number will be copied to that set
   - Or click **Match Aliases** to fuzzy-match the visible channel names against each set's name and aliases, then accept the suggestions you want

6. **Configure device**: Click "Config Device" to create a map of Program # → Virtual Channel

## GUI Layout

```
+-------------------------+----------------------------------------------+
| Channel List            | ESPN [→]       CNN [→]       Set 3 [→]  ... |
| (from Chrome)           | [Name] [Prog#] [VCh]                         |
|                         |                                              |
| [Load]                  | Set 5 [→]      Set 6 [→]     ...             |
|                         |                                              |
| ☐ Channel 1             |     (4 columns x 15 rows = 60 sets)          |
| ☐ Channel 2             |                                              |
| ☐ Channel 3             |                                              |
| ...                     |                                              |
| [Remove Duplicates]     |                                              |
| [Remove Freq 999000]    |                                              |
| [Match Aliases]         | [Config Device]  [Edit Config]               |
+-------------------------+----------------------------------------------+
```

## Edit Box Layout per Set

Each set contains:
- **Row 1**: Label (INI name or "Set X") | Arrow button (→)
- **Row 2**: Name (editable) | Program # (editable) | Virtual Channel (read-only, from INI; change it with Edit Config)

## Search Box

- Type in the search box to filter channels by name (case-insensitive)
- Filters as you type
- Clear the search box to restore the full list

## Filter Buttons

- **Remove Duplicates**: Removes channels with duplicate names, keeping the one with the lowest program number
- **Remove Freq 999000**: Removes all channels with frequency 999000
- **Match Aliases**: Fuzzy-matches the channel names currently shown in the list against each set's name and aliases

## Edit Config

**Edit Config** opens a window for all 60 sets. Select a set and edit:

- **Name** — the label shown on the set
- **Virtual Channel** — the virtual channel used by Config Device
- **Aliases** — other names this channel may appear as, one per line or separated by `|`

Save writes `ChannelSets.ini` and updates the labels and virtual channels on the main window. Assignments already typed into the name and program boxes are left as they are.

## Match Aliases

**Match Aliases** compares every channel currently visible in the list (including an active search) with each set's name and aliases.

- An alias matches when each of its words appears in the channel name, so `nick` matches `HD Nick BB`. Wording such as HD, East, or TV is ignored, including when it is stuck to the name (`truTV` matches `tru TV` and does not match `TRAV HD`)
- The word `network` or `channel` by itself is not a high-confidence match, so an alias of just `network` does not match Paramount Network and Cartoon Network. Use the fuller name, such as `Paramount Network`
- Small typos can match, but they are left unchecked so you can review them
- Different station numbers are not treated as the same channel (`ESPN` does not match `ESPN2`, and channel 5 does not match channel 7). Put the full name in the alias list when the number is part of the name

The suggestion window lists the best match for each set, with the matched alias and score. Strong matches for sets that do not already have an assignment start checked. Check or uncheck rows, then **Accept Checked** to copy the channel name and program number into those sets (the same result as the arrow button).

## Save/Load Assignments

- **Save Assignments**: Saves all channel assignment sets to a text file
- **Load Assignments**: Loads channel assignments from a previously saved file
- **Clear All**: Clears all channel assignments (with confirmation)

Saved file format:
```
Set1=Channel Name|Program Number|Virtual Channel
Set5=ESPN|1234|101
```

## Right-Click to Copy

- Right-click any row in the ListView to copy the channel name to clipboard
- A tooltip confirms the copied name

## Accessing the Map

After clicking "Config Device", the `ProgramChannelMap` global variable contains the mapping:

```autohotkey
; Example usage in your logic:
for progNum, virtualCh in ProgramChannelMap {
    ; progNum is the program number from the assigned channel
    ; virtualCh is the virtual channel from the INI
    MsgBox "Program " progNum " maps to Virtual Channel " virtualCh
}
```

## Expected Chrome Element Format

The script expects the `channel_selector` element to contain ListItem elements with names in this format:
```
channel X - Program #Y - {Channel Name} - Frequency Z
```

Example:
```
channel 5 - Program #123 - ESPN HD - Frequency 567
```

## Troubleshooting

- **"Chrome window not found"**: Make sure Chrome is running
- **"channel_selector element not found"**: The page with the channel selector must be visible in Chrome
- **"No channels found"**: The channel_selector element may be empty or the format doesn't match

## Customization

To modify the GUI layout, edit these values in `Main()`:
- `setWidth`, `setHeight` - Size of each channel set
- `colGap`, `rowGap` - Spacing between sets
- Window size in `MainGui.Show()`
