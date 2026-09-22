# Channel Mapper - AHK v2 GUI

A GUI application for mapping channels from a Chrome-based channel selector to virtual channel assignments.

## Files

- `ChannelMapper.ahk` - Main script (requires UIA-v2 library)
- `ChannelMapper_Standalone.ahk` - Standalone version with built-in UIA (no external library needed)
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

1. **Configure the INI file**: Edit `ChannelSets.ini` to set the default names and virtual channels for each of the 60 sets:
   ```ini
   [Set1]
   Name=ESPN
   VirtualChannel=101
   ```

2. **Open Chrome**: Navigate to the page with the `channel_selector` element

3. **Run the script**: Double-click `ChannelMapper.ahk` or `ChannelMapper_Standalone.ahk`

4. **Load channels**: Click the "Load" button to scan Chrome for channels

5. **Assign channels**:
   - Check (tick) a channel in the ListView (only one can be checked at a time)
   - Click the arrow button (→) next to any set to assign that channel
   - The channel name and program number will be copied to that set

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
|                         | [Config Device]                              |
| [Remove Duplicates]     |                                              |
| [Remove Freq 999000]    |                                              |
+-------------------------+----------------------------------------------+
```

## Edit Box Layout per Set

Each set contains:
- **Row 1**: Label (INI name or "Set X") | Arrow button (→)
- **Row 2**: Name (editable) | Program # (editable) | Virtual Channel (read-only, from INI)

## Search Box

- Type in the search box to filter channels by name (case-insensitive)
- Filters as you type
- Clear the search box to restore the full list

## Filter Buttons

- **Remove Duplicates**: Removes channels with duplicate names, keeping the one with the lowest program number
- **Remove Freq 999000**: Removes all channels with frequency 999000

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
