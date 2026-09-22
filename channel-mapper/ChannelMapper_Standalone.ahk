#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; STANDALONE VERSION - No external UIA library required
; ============================================================

; Include save/load functionality
#Include "ChannelSetIO.ahk"

; Global variables
global ChannelList := []
global FullChannelList := []
global ChannelSets := []
global ProgramChannelMap := Map()
global CurrentCheckedRow := 0
global CheckedChannel := ""

; GUI Controls references
global MainGui := ""
global LV := ""
global LoadBtn := ""
global ConfigBtn := ""
global SearchEdit := ""

; Initialize and show GUI
Main()

Main() {
    global MainGui, LV, LoadBtn, ConfigBtn, ChannelSets
    
    ; Load INI settings
    LoadINISettings()
    
    ; Create main GUI
    MainGui := Gui("+Resize", "Channel Mapper")
    MainGui.SetFont("s9", "Segoe UI")
    MainGui.OnEvent("Close", (*) => ExitApp())
    MainGui.OnEvent("Size", GuiResize)
    
    ; Left panel - ListView
    MainGui.AddText("xm y5 w300 h20", "Channel List (from Chrome)")
    LoadBtn := MainGui.AddButton("x+10 yp-3 w80 h26", "Load")
    LoadBtn.OnEvent("Click", LoadChannels)
    
    ; Search box
    MainGui.AddText("xm y32 w50 h20", "Search:")
    SearchEdit := MainGui.AddEdit("x+5 yp-2 w345 h22")
    SearchEdit.OnEvent("Change", OnSearchChange)
    
    LV := MainGui.AddListView("xm y55 w400 h495 Checked -Multi", ["Channel", "Program #", "Name", "Frequency"])
    LV.OnEvent("ItemCheck", OnItemCheck)
    SetupListViewRightClick(LV)
    
    ; Set column widths
    LV.ModifyCol(1, 70)
    LV.ModifyCol(2, 80)
    LV.ModifyCol(3, 150)
    LV.ModifyCol(4, 80)
    
    ; Buttons below ListView
    RemoveDupBtn := MainGui.AddButton("xm y560 w195 h26", "Remove Duplicates")
    RemoveDupBtn.OnEvent("Click", RemoveDuplicates)
    
    Remove999Btn := MainGui.AddButton("x+10 yp w195 h26", "Remove Freq 999000")
    Remove999Btn.OnEvent("Click", RemoveFreq999000)
    
    ; Save/Load buttons
    SaveBtn := MainGui.AddButton("xm y590 w130 h26", "Save Assignments")
    SaveBtn.OnEvent("Click", SaveChannelSets)
    
    LoadBtn2 := MainGui.AddButton("x+5 yp w130 h26", "Load Assignments")
    LoadBtn2.OnEvent("Click", LoadChannelSets)
    
    ClearBtn := MainGui.AddButton("x+5 yp w130 h26", "Clear All")
    ClearBtn.OnEvent("Click", ClearAllChannelSets)
    
    ; Right panel - 60 channel sets (4 columns x 15 rows)
    MainGui.AddText("x420 y5 w700 h20 Center", "Channel Assignment Sets")
    
    ; Create 60 sets of edit boxes
    startX := 420
    startY := 30
    setWidth := 170
    setHeight := 42
    colGap := 5
    rowGap := 2
    
    Loop 60 {
        setIndex := A_Index
        col := Mod(setIndex - 1, 4)
        row := (setIndex - 1) // 4
        
        x := startX + (col * (setWidth + colGap))
        y := startY + (row * (setHeight + rowGap))
        
        ; Create the set container
        CreateChannelSet(setIndex, x, y, setWidth, setHeight)
    }
    
    ; Config Device button at bottom
    ConfigBtn := MainGui.AddButton("x420 y" (startY + (15 * (setHeight + rowGap)) + 10) " w150 h30", "Config Device")
    ConfigBtn.OnEvent("Click", ConfigDevice)
    
    ; Show GUI
    MainGui.Show("w1130 h700")
}

CreateChannelSet(index, x, y, width, height) {
    global MainGui, ChannelSets
    
    set := {}
    set.Index := index
    
    ; Get default values from loaded INI
    defaultName := ""
    virtualChannel := ""
    for item in ChannelSets {
        if (item.Index = index) {
            defaultName := item.DefaultName
            virtualChannel := item.VirtualChannel
            break
        }
    }
    
    ; Row 1: Label (INI name or "Set X") and Arrow button
    labelText := (defaultName != "") ? defaultName : "Set " index
    MainGui.AddText("x" x " y" y " w" (width - 28) " h16 +0x200", labelText)
    
    arrowBtn := MainGui.AddButton("x" (x + width - 25) " yp-2 w25 h20", "→")
    arrowBtn.OnEvent("Click", ArrowClick.Bind(index))
    set.ArrowBtn := arrowBtn
    
    ; Row 2: Name and Program #
    nameEdit := MainGui.AddEdit("x" x " y" (y + 20) " w80 h20", "")
    set.NameEdit := nameEdit
    
    progEdit := MainGui.AddEdit("x" (x + 85) " yp w40 h20", "")
    set.ProgramEdit := progEdit
    
    vchEdit := MainGui.AddEdit("x" (x + 130) " yp w35 h20 ReadOnly", virtualChannel)
    set.VirtualChannelEdit := vchEdit
    
    ; Store set info
    set.DefaultName := defaultName
    set.VirtualChannel := virtualChannel
    
    ; Update or add to ChannelSets
    found := false
    for i, item in ChannelSets {
        if (item.Index = index) {
            ChannelSets[i] := set
            found := true
            break
        }
    }
    if (!found)
        ChannelSets.Push(set)
}

LoadINISettings() {
    global ChannelSets
    
    iniPath := A_ScriptDir "\ChannelSets.ini"
    
    ; Check if INI exists
    if !FileExist(iniPath) {
        ; Create default INI
        CreateDefaultINI(iniPath)
    }
    
    ; Load settings for all 60 sets
    ChannelSets := []
    Loop 60 {
        section := "Set" A_Index
        set := {}
        set.Index := A_Index
        set.DefaultName := IniRead(iniPath, section, "Name", "")
        set.VirtualChannel := IniRead(iniPath, section, "VirtualChannel", "")
        ChannelSets.Push(set)
    }
}

CreateDefaultINI(path) {
    content := ""
    Loop 60 {
        content .= "[Set" A_Index "]`n"
        content .= "Name=`n"
        content .= "VirtualChannel=`n`n"
    }
    FileAppend(content, path)
}

LoadChannels(*) {
    global ChannelList, FullChannelList, LV, CurrentCheckedRow, CheckedChannel, SearchEdit
    
    ; Clear existing items
    LV.Delete()
    ChannelList := []
    FullChannelList := []
    CurrentCheckedRow := 0
    CheckedChannel := ""
    SearchEdit.Value := ""
    
    ; Use UIA to get channels from Chrome
    try {
        channels := GetChannelsFromChrome()
        
        for channel in channels {
            ChannelList.Push(channel)
            FullChannelList.Push(channel)
            LV.Add("", channel.Channel, channel.ProgramNum, channel.Name, channel.Frequency)
        }
        
        if (ChannelList.Length = 0)
            MsgBox("No channels found. Make sure Chrome is open with the channel selector visible.", "Load Channels", "Icon!")
    } catch as e {
        MsgBox("Error loading channels: " e.Message "`n`nMake sure Chrome is open with the channel selector visible.", "Error", "Icon!")
    }
}

OnSearchChange(*) {
    global ChannelList, FullChannelList, LV, CurrentCheckedRow, CheckedChannel, SearchEdit
    
    searchText := SearchEdit.Value
    
    ; Clear current selection
    CurrentCheckedRow := 0
    CheckedChannel := ""
    
    ; Filter the list
    LV.Delete()
    ChannelList := []
    
    for channel in FullChannelList {
        if (searchText = "" || InStr(channel.Name, searchText, false)) {
            ChannelList.Push(channel)
            LV.Add("", channel.Channel, channel.ProgramNum, channel.Name, channel.Frequency)
        }
    }
}

RemoveDuplicates(*) {
    global ChannelList, FullChannelList, LV, CurrentCheckedRow, CheckedChannel, SearchEdit
    
    if (FullChannelList.Length = 0) {
        MsgBox("No channels loaded.", "Remove Duplicates", "Icon!")
        return
    }
    
    ; Build a map of name -> channel with lowest program number
    nameMap := Map()
    for channel in FullChannelList {
        name := channel.Name
        if (!nameMap.Has(name) || Integer(channel.ProgramNum) < Integer(nameMap[name].ProgramNum)) {
            nameMap[name] := channel
        }
    }
    
    ; Rebuild full channel list with unique names
    originalCount := FullChannelList.Length
    FullChannelList := []
    for name, channel in nameMap {
        FullChannelList.Push(channel)
    }
    
    ; Sort by program number
    SortChannelsByProgram(FullChannelList)
    
    ; Clear search and refresh
    SearchEdit.Value := ""
    ChannelList := []
    for channel in FullChannelList {
        ChannelList.Push(channel)
    }
    
    ; Refresh ListView
    LV.Delete()
    CurrentCheckedRow := 0
    CheckedChannel := ""
    for channel in ChannelList {
        LV.Add("", channel.Channel, channel.ProgramNum, channel.Name, channel.Frequency)
    }
    
    removed := originalCount - FullChannelList.Length
    MsgBox("Removed " removed " duplicate channels.`nRemaining: " FullChannelList.Length, "Remove Duplicates", "Iconi")
}

RemoveFreq999000(*) {
    global ChannelList, FullChannelList, LV, CurrentCheckedRow, CheckedChannel, SearchEdit
    
    if (FullChannelList.Length = 0) {
        MsgBox("No channels loaded.", "Remove Frequency 999000", "Icon!")
        return
    }
    
    ; Filter out channels with frequency 999000 from full list
    originalCount := FullChannelList.Length
    newList := []
    for channel in FullChannelList {
        if (channel.Frequency != "999000") {
            newList.Push(channel)
        }
    }
    FullChannelList := newList
    
    ; Clear search and refresh
    SearchEdit.Value := ""
    ChannelList := []
    for channel in FullChannelList {
        ChannelList.Push(channel)
    }
    
    ; Refresh ListView
    LV.Delete()
    CurrentCheckedRow := 0
    CheckedChannel := ""
    for channel in ChannelList {
        LV.Add("", channel.Channel, channel.ProgramNum, channel.Name, channel.Frequency)
    }
    
    removed := originalCount - FullChannelList.Length
    MsgBox("Removed " removed " channels with frequency 999000.`nRemaining: " FullChannelList.Length, "Remove Frequency 999000", "Iconi")
}

SortChannelsByProgram(arr) {
    ; Simple bubble sort by program number
    n := arr.Length
    Loop n - 1 {
        i := A_Index
        Loop n - i {
            j := A_Index
            if (Integer(arr[j].ProgramNum) > Integer(arr[j + 1].ProgramNum)) {
                temp := arr[j]
                arr[j] := arr[j + 1]
                arr[j + 1] := temp
            }
        }
    }
}

GetChannelsFromChrome() {
    channels := []
    
    ; Find Chrome window
    chromeHwnd := WinExist("ahk_exe chrome.exe")
    if (!chromeHwnd) {
        throw Error("Chrome window not found")
    }
    
    ; Initialize UIA
    static IUIAutomation := "{ff48dba4-60ef-4201-aa87-54103eef594e}"
    static IID_IUIAutomation := "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}"
    
    uia := ComObject(IUIAutomation, IID_IUIAutomation)
    
    ; Get Chrome element
    chromeEl := ComValue(13, 0)
    ComCall(6, uia, "Ptr", chromeHwnd, "Ptr*", &chromeEl)
    
    if (!chromeEl.Ptr) {
        throw Error("Could not get Chrome UI element")
    }
    
    ; Create condition to find channel_selector by AutomationId
    ; UIA_AutomationIdPropertyId = 30011
    condition := ComValue(13, 0)
    ComCall(23, uia, "Int", 30011, "Str", "channel_selector", "Ptr*", &condition)
    
    ; Find the element (TreeScope_Descendants = 4)
    selectorEl := ComValue(13, 0)
    ComCall(5, chromeEl, "Int", 4, "Ptr", condition, "Ptr*", &selectorEl)
    
    if (!selectorEl.Ptr) {
        ; Try finding by Name property (30005)
        condition2 := ComValue(13, 0)
        ComCall(23, uia, "Int", 30005, "Str", "channel_selector", "Ptr*", &condition2)
        ComCall(5, chromeEl, "Int", 4, "Ptr", condition2, "Ptr*", &selectorEl)
    }
    
    if (!selectorEl.Ptr) {
        throw Error("channel_selector element not found in Chrome. Make sure the page with the channel selector is open.")
    }
    
    ; Create condition for ListItem type (UIA_ListItemControlTypeId = 50007)
    listItemCondition := ComValue(13, 0)
    ComCall(23, uia, "Int", 30003, "Int", 50007, "Ptr*", &listItemCondition)
    
    ; Find all ListItems
    listItems := ComValue(13, 0)
    ComCall(6, selectorEl, "Int", 4, "Ptr", listItemCondition, "Ptr*", &listItems)
    
    if (!listItems.Ptr) {
        throw Error("No list items found in channel_selector")
    }
    
    ; Get count of items
    itemCount := 0
    ComCall(3, listItems, "Int*", &itemCount)
    
    ; Iterate through items
    Loop itemCount {
        item := ComValue(13, 0)
        ComCall(4, listItems, "Int", A_Index - 1, "Ptr*", &item)
        
        if (item.Ptr) {
            ; Get name property
            nameBstr := 0
            ComCall(23, item, "Ptr*", &nameBstr)
            
            if (nameBstr) {
                itemName := StrGet(nameBstr, "UTF-16")
                DllCall("OleAut32\SysFreeString", "Ptr", nameBstr)
                
                ; Parse: "channel x - Program #x - {name} - Frequency x"
                parsed := ParseChannelString(itemName)
                if (parsed)
                    channels.Push(parsed)
            }
        }
    }
    
    return channels
}

ParseChannelString(str) {
    ; Parse: "channel x - Program #x - {name} - Frequency x"
    ; Example: "channel 5 - Program #123 - ESPN HD - Frequency 567"
    
    if (!str || str = "")
        return false
    
    channel := {}
    
    ; Use regex to parse
    if RegExMatch(str, "i)channel\s+(\d+)\s*-\s*Program\s*#(\d+)\s*-\s*(.+?)\s*-\s*Frequency\s+(\d+)", &match) {
        channel.Channel := match[1]
        channel.ProgramNum := match[2]
        channel.Name := Trim(match[3])
        channel.Frequency := match[4]
        return channel
    }
    
    return false
}

OnItemCheck(LV, rowNum, checked) {
    global CurrentCheckedRow, CheckedChannel
    
    if (checked) {
        ; Uncheck previous row if different
        if (CurrentCheckedRow > 0 && CurrentCheckedRow != rowNum) {
            LV.Modify(CurrentCheckedRow, "-Check")
        }
        CurrentCheckedRow := rowNum
        
        ; Store the actual channel data from the ListView row (handles sorting)
        CheckedChannel := {}
        CheckedChannel.Channel := LV.GetText(rowNum, 1)
        CheckedChannel.ProgramNum := LV.GetText(rowNum, 2)
        CheckedChannel.Name := LV.GetText(rowNum, 3)
        CheckedChannel.Frequency := LV.GetText(rowNum, 4)
    } else {
        if (CurrentCheckedRow = rowNum) {
            CurrentCheckedRow := 0
            CheckedChannel := ""
        }
    }
}

ArrowClick(setIndex, *) {
    global ChannelSets, CurrentCheckedRow, CheckedChannel
    
    ; Check if a channel is selected
    if (CurrentCheckedRow = 0 || CheckedChannel = "") {
        MsgBox("Please check a channel in the list first.", "No Channel Selected", "Icon!")
        return
    }
    
    ; Find the target set
    for set in ChannelSets {
        if (set.Index = setIndex) {
            ; Update the Name and Program # edit boxes using stored channel data
            set.NameEdit.Value := CheckedChannel.Name
            set.ProgramEdit.Value := CheckedChannel.ProgramNum
            break
        }
    }
}

ConfigDevice(*) {
    global ChannelSets, ProgramChannelMap
    
    ; Clear existing map
    ProgramChannelMap := Map()
    
    ; Build map from all sets that have both program number and virtual channel
    configuredCount := 0
    for set in ChannelSets {
        progNum := set.ProgramEdit.Value
        vChannel := set.VirtualChannelEdit.Value
        
        if (progNum != "" && vChannel != "") {
            ProgramChannelMap[progNum] := vChannel
            configuredCount++
        }
    }
    
    ; Show confirmation
    mapDisplay := "Configured " configuredCount " channel mappings:`n`n"
    mapDisplay .= "Program # → Virtual Channel`n"
    mapDisplay .= "─────────────────────────`n"
    
    count := 0
    for progNum, vCh in ProgramChannelMap {
        mapDisplay .= progNum " → " vCh "`n"
        count++
        if (count >= 20) {
            mapDisplay .= "... and " (ProgramChannelMap.Count - 20) " more`n"
            break
        }
    }
    
    MsgBox(mapDisplay, "Config Device - Map Created", "Iconi")
}

GuiResize(thisGui, minMax, width, height) {
    if (minMax = -1) ; Minimized
        return
    
    ; Adjust ListView height on resize
    global LV
    if (IsObject(LV))
        LV.Move(,, , height - 80)
}
