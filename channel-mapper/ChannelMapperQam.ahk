#Requires AutoHotkey v2.0
#SingleInstance Force

; Include UIA library if available (place UIA.ahk in Lib folder or same directory)
; Download from: https://github.com/Descolada/UIA-v2
#Include UIA.ahk

; Include save/load functionality
#Include "ChannelSetIO.ahk"
#Include "ChannelAlias.ahk"
#Include "ChannelLocals.ahk"

OPEN_TAG := "<QAM_Mapping view=`"Mappings`">"
CLOSE_TAG := "</QAM_Mapping>"
SOURCE_OPEN := "<Source_ID>"
SOURCE_CLOSE := "</Source_ID>"
FORM_FIELD := "Import"
DEFAULT_PART_TYPE := "text/xml"
UPLOAD_NAME := "import.xml"
DOWNLOAD_NAME := "download.xml"
BROWSER_UA := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

global Ui := {}
global Tests := {failures: 0}
global LastGeneratedXml := ""

if (A_Args.Length >= 1 && StrLower(A_Args[1]) == "/selftest")
    ExitApp(RunSelfTest())

; Global variables
global ChannelList := []
global FullChannelList := []
global ChannelSets := []
global ProgramChannelMap := Map()
global CurrentCheckedRow := 0
global CheckedChannel := ""

    global MainGui, LV, LoadBtn, ConfigBtn, ChannelSets
    
    ; Load INI settings
    LoadINISettings()
    
    ; Create main GUI
    MainGui := Gui("+Resize", "Vecima Channel Mapper")
    MainGui.SetFont("s9", "Segoe UI")
    MainGui.OnEvent("Close", CloseGui)
    MainGui.OnEvent("Size", GuiResize)
    
    ; Left panel - ListView
    MainGui.AddText("xm y5 w300 h20", "Channel List (from Chrome)")
    LoadBtn := MainGui.AddButton("x+10 yp-3 w80 h26", "Load")
    LoadBtn.OnEvent("Click", LoadChannels)
    
    ; Search box
    MainGui.AddText("xm y32 w50 h20", "Search:")
    SearchEdit := MainGui.AddEdit("x+5 yp-2 w345 h22")
    SearchEdit.OnEvent("Change", OnSearchChange)
    
    LV := MainGui.AddListView("xm y55 w400 h593 Checked -Multi", ["Channel", "Program #", "Name", "Frequency"])
    LV.OnEvent("ItemCheck", OnItemCheck)
    SetupListViewRightClick(LV)
    
    ; Set column widths
    LV.ModifyCol(1, 70)
    LV.ModifyCol(2, 80)
    LV.ModifyCol(3, 150)
    LV.ModifyCol(4, 80)
    
    ; Buttons below ListView
    RemoveDupBtn := MainGui.AddButton("xm y656 w195 h26", "Remove Duplicates")
    RemoveDupBtn.OnEvent("Click", RemoveDuplicates)
    
    Remove999Btn := MainGui.AddButton("x+10 yp w195 h26", "Remove Freq 999000")
    Remove999Btn.OnEvent("Click", RemoveFreq999000)
    
    ; Save/Load buttons
    SaveBtn := MainGui.AddButton("xm y686 w130 h26", "Save Assignments")
    SaveBtn.OnEvent("Click", SaveChannelSets)
    
    LoadBtn2 := MainGui.AddButton("x+5 yp w130 h26", "Load Assignments")
    LoadBtn2.OnEvent("Click", LoadChannelSets)
    
    ClearBtn := MainGui.AddButton("x+5 yp w130 h26", "Clear All")
    ClearBtn.OnEvent("Click", ClearAllChannelSets)

    MatchAliasBtn := MainGui.AddButton("xm y716 w195 h26", "Match Aliases")
    MatchAliasBtn.OnEvent("Click", SuggestAliasMatches)

    GetLocalsBtn := MainGui.AddButton("x+10 yp w195 h26", "Get Locals")
    GetLocalsBtn.OnEvent("Click", SuggestLocalMatches)
    
    ; Right panel - 60 channel sets (4 columns x 15 rows)
    MainGui.AddText("x420 y5 w700 h20 Center", "Channel Map")
    
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
    
    ; Config buttons at the bottom of the set grid
    configY := startY + (15 * (setHeight + rowGap)) + 10
    ConfigBtn := MainGui.AddButton("x420 y" configY " w150 h30", "Config Device")
    ConfigBtn.OnEvent("Click", ConfigDevice)

    EditConfigBtn := MainGui.AddButton("x580 y" configY " w150 h30", "Edit Config")
    EditConfigBtn.OnEvent("Click", EditChannelConfig)

    ; Far right panel - QAM XML import
    CreateQamPanel(1130)
    
    ; Show GUI
    MainGui.Show("w1565 h760")


CreateChannelSet(index, x, y, width, height) {
    global MainGui, ChannelSets
    
    set := {}
    set.Index := index
    
    ; Get default values from loaded INI
    defaultName := ""
    virtualChannel := ""
    aliases := []
    for item in ChannelSets {
        if (item.Index = index) {
            defaultName := item.DefaultName
            virtualChannel := item.VirtualChannel
            if (item.HasOwnProp("Aliases"))
                aliases := item.Aliases
            break
        }
    }
    
    ; Row 1: Label (INI name or "Set X") and Arrow button
    labelCtrl := MainGui.AddText("x" x " y" y " w" (width - 28) " h16 +0x200", DisplayLabel(defaultName, index))
    set.Label := labelCtrl
    
    arrowBtn := MainGui.AddButton("x" (x + width - 25) " yp-2 w25 h20", "→")
    arrowBtn.OnEvent("Click", ArrowClick.Bind(index))
    set.ArrowBtn := arrowBtn
    
    ; Row 2: Name and Program #
    nameEdit := MainGui.AddEdit("x" x " y" (y + 20) " w80 h20", "")
    set.NameEdit := nameEdit
    
    progEdit := MainGui.AddEdit("x" (x + 85) " yp w40 h20", "")
    progEdit.OnEvent("Change", RefreshReplacementSoon)
    set.ProgramEdit := progEdit
    
    vchEdit := MainGui.AddEdit("x" (x + 130) " yp w35 h20 ReadOnly", virtualChannel)
    vchEdit.OnEvent("Change", RefreshReplacementSoon)
    set.VirtualChannelEdit := vchEdit
    
    ; Store set info
    set.DefaultName := defaultName
    set.VirtualChannel := virtualChannel
    set.Aliases := aliases
    
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
        set.Aliases := ParseAliasList(IniRead(iniPath, section, "Aliases", ""))
        ChannelSets.Push(set)
    }
}

CreateDefaultINI(path) {
    content := ""
    Loop 60 {
        content .= "[Set" A_Index "]`n"
        content .= "Name=`n"
        content .= "VirtualChannel=`n"
        content .= "Aliases=`n`n"
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
        MsgBox("Error loading channels: " e.Message "`n`nMake sure:`n1. UIA.ahk library is in Lib folder`n2. Chrome is open with the channel selector visible", "Error", "Icon!")
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
    if !WinExist("ahk_exe chrome.exe") {
        throw Error("Chrome window not found")
    }
    
    ; Get Chrome element using UIA
    try {
        chromeEl := UIA.ElementFromHandle(WinExist("ahk_exe chrome.exe"))
    } catch {
        throw Error("Could not get Chrome UI element")
    }
    
    ; Find channel_selector element by AutomationId
    try {
        selectorEl := chromeEl.FindElement({AutomationId: "channel_selector"})
        
        if (!selectorEl) {
            ; Try finding by Name
            selectorEl := chromeEl.FindElement({Name: "channel_selector"})
        }
        
        if (!selectorEl) {
            throw Error("channel_selector element not found in Chrome")
        }
        
        ; Get all ListItem children
        listItems := selectorEl.FindElements({Type: "ListItem"})
        
        ; Parse each list item
        for item in listItems {
            itemName := item.Name
            
            ; Parse: "channel x - Program #x - {name} - Frequency x"
            parsed := ParseChannelString(itemName)
            if (parsed)
                channels.Push(parsed)
        }
    } catch as e {
        throw Error("Error finding channels: " e.Message)
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
    
    ; Keep the list above the button rows (they start at y656).
    global LV
    if (!IsObject(LV))
        return

    lvHeight := height - 167
    if (lvHeight > 593)
        lvHeight := 593
    if (lvHeight < 160)
        lvHeight := 160
    LV.Move(,, , lvHeight)
}

; ---------------------------------------------------------------- QAM XML panel

CreateQamPanel(x) {
    global MainGui, Ui
    saved := LoadSettings()
    g := MainGui
    w := 420
    fieldX := x + 85
    fieldW := w - 85

    g.AddText("x" x " y5 w" w " h20 Center", "QAM XML Import")

    g.AddText("x" x " y30 w" w, "Upload URL")
    Ui.Url := g.AddEdit("x" x " y48 w" w " h22")

    g.AddText("x" x " y82 w80", "Username")
    Ui.Username := g.AddEdit("x" fieldX " y78 w" fieldW " h22")
    g.AddText("x" x " y108 w80", "Password")
    Ui.Password := g.AddEdit("x" fieldX " y104 w" fieldW " h22 Password")
    g.AddText("x" x " y134 w80", "New Source ID")
    Ui.SourceId := g.AddEdit("x" fieldX " y130 w120 h22")

    g.AddText("x" x " y162 w40", "Unit")
    Ui.UnitLow := g.AddRadio("x" fieldX " y162 w100 Group", "Low (1-20)")
    Ui.UnitMid := g.AddRadio("x+5 yp w110", "Medium (21-40)")
    Ui.UnitHigh := g.AddRadio("x+5 yp w100", "High (41-60)")
    for ctrl in [Ui.UnitLow, Ui.UnitMid, Ui.UnitHigh]
        ctrl.OnEvent("Click", RefreshReplacementSoon)

    g.AddText("x" x " y186 w" w, "QAM_Mapping replacement (generated from the channel map)")
    Ui.Replacement := g.AddEdit("x" x " y204 w" w " h304 Multi WantReturn")
    SendMessage(0xC5, 20000000, 0, Ui.Replacement.Hwnd)

    Ui.DownloadBtn := g.AddButton("x" x " y516 w135 h28", "Download XML")
    Ui.DownloadBtn.OnEvent("Click", DownloadXml)
    Ui.RewriteBtn := g.AddButton("x+7 yp w135 h28", "Rewrite XML")
    Ui.RewriteBtn.OnEvent("Click", (*) => RunJob(false))
    Ui.UploadBtn := g.AddButton("x+7 yp w136 h28", "Rewrite and Upload")
    Ui.UploadBtn.OnEvent("Click", (*) => RunJob(true))

    g.AddText("x" x " y552 w" w, "Log")
    Ui.Log := g.AddEdit("x" x " y570 w" w " h180 ReadOnly Multi")
    SendMessage(0xC5, 5000000, 0, Ui.Log.Hwnd)

    Ui.SourceId.Value := saved.SourceId
    Ui.Url.Value := saved.Url
    Ui.Username.Value := saved.Username
    Ui.Password.Value := saved.Password
    SetUnit(saved.Unit)

    RefreshReplacement()
    ; Load, Clear, Match Aliases and Edit Config set the boxes from code, so poll as well.
    SetTimer(PollReplacement, 1000)
}

SelectedUnit() {
    global Ui
    if (Ui.UnitMid.Value)
        return "Medium"
    if (Ui.UnitHigh.Value)
        return "High"
    return "Low"
}

SetUnit(unit) {
    global Ui
    Ui.UnitLow.Value := unit != "Medium" && unit != "High"
    Ui.UnitMid.Value := unit == "Medium"
    Ui.UnitHigh.Value := unit == "High"
}

UnitSetRange(unit) {
    if (unit == "Medium")
        return {first: 21, last: 40}
    if (unit == "High")
        return {first: 41, last: 60}
    return {first: 1, last: 20}
}

BuildMappingXml() {
    global ChannelSets
    range := UnitSetRange(SelectedUnit())
    xml := ""
    for set in ChannelSets {
        if (set.Index < range.first || set.Index > range.last)
            continue
        if !(set.HasOwnProp("ProgramEdit") && set.HasOwnProp("VirtualChannelEdit"))
            continue
        prog := Trim(set.ProgramEdit.Value)
        vch := Trim(set.VirtualChannelEdit.Value)
        if (prog == "" || vch == "")
            continue
        block := OPEN_TAG "`r`n"
            . "<EIA>" XmlEscape(vch) "</EIA>`r`n"
            . "<destip></destip>`r`n"
            . "<destport>0</destport>`r`n"
            . "<SourceId>" XmlEscape(prog) "</SourceId>`r`n"
            . CLOSE_TAG
        xml .= (xml == "" ? "" : "`r`n") . block
    }
    return xml
}

XmlEscape(text) {
    text := StrReplace(text, "&", "&amp;")
    text := StrReplace(text, "<", "&lt;")
    return StrReplace(text, ">", "&gt;")
}

RefreshReplacement(*) {
    global Ui, LastGeneratedXml
    if !Ui.HasProp("Replacement")
        return
    xml := BuildMappingXml()
    if (xml == LastGeneratedXml)
        return
    LastGeneratedXml := xml
    Ui.Replacement.Value := xml
}

RefreshReplacementSoon(*) {
    SetTimer(RefreshReplacement, -100)
}

PollReplacement() {
    RefreshReplacement()
}

CloseGui(*) {
    try
        SaveSettings(CollectForm())
    catch as err
        MsgBox(err.Message, "QAM XML Import", "Icon!")
    ExitApp()
}

DownloadPath() {
    return A_ScriptDir "\" DOWNLOAD_NAME
}

ImportPath() {
    return A_ScriptDir "\" UPLOAD_NAME
}

DownloadXml(*) {
    SetBusy(true)
    try {
        form := CollectForm()
        SaveSettings(form)
        ValidateUpload(form)
        Log("Downloading from " form.Url)
        if (AuthorizationHeader(form.Username, form.Password) != "")
            Log("Authorization: Basic (set)")
        else
            Log("Authorization: (none)")
        response := SendMultipart(form, BuildDownloadMultipart())
        Log("HTTP " response.status " " response.statusText)
        if (response.finalUrl != "")
            Log("Final URL: " response.finalUrl)
        if (response.status < 200 || response.status >= 300) {
            if (response.body != "")
                Log(response.body)
            throw Error("Download returned HTTP " response.status ". The log has the response.")
        }
        if (response.bytes.Size = 0)
            throw Error("The download response was empty.")
        path := DownloadPath()
        WriteRaw(path, response.bytes)
        Log("Saved " path " (" response.bytes.Size " bytes).")
    } catch as err {
        detail := err.Message
        if (err.Line)
            Log("Error (line " err.Line "): " detail)
        else
            Log("Error: " detail)
        MsgBox(detail, "QAM XML Import", "Icon!")
    } finally {
        SetBusy(false)
    }
}

RunJob(doUpload) {
    global Ui
    SetBusy(true)
    try {
        RefreshReplacement()
        form := CollectForm()
        SaveSettings(form)
        form := ValidateReady(form, doUpload)

        range := UnitSetRange(form.Unit)
        Log(form.Unit " unit: mapping sets " range.first "-" range.last)
        Log("Reading " form.XmlPath)
        original := ReadRaw(form.XmlPath)
        result := RewriteXml(original, form.Replacement, form.SourceId)
        outPath := ImportPath()

        if (result.sourceIdsReplaced = 0)
            Log("Warning: no <Source_ID> number was changed.")
        if (doUpload && result.sourceIdsReplaced = 0) {
            answer := MsgBox(
                "No Source_ID number was changed.`n`nUpload the file anyway?",
                "QAM XML Import", "YesNo Icon!")
            if (answer != "Yes") {
                WriteRaw(outPath, result.bytes)
                Log("Upload cancelled. Wrote " outPath)
                return
            }
        }

        WriteRaw(outPath, result.bytes)
        Log("Encoding: " result.encoding)
        Log("Replaced the QAM_Mapping block, including both tags, at bytes " result.mappingStart "-" (result.mappingEnd - 1)
            . " (" result.bytesRemoved " bytes removed, " result.replacementBytes " bytes inserted).")
        Log("Source_ID numbers updated: " result.sourceIdsReplaced)
        if (result.sourceIdsWithoutNumber > 0)
            Log("Source_ID tags left unchanged because they had no number: " result.sourceIdsWithoutNumber)
        if (result.sourceIdsRemovedWithMapping > 0)
            Log("Source_ID tags inside the old mapping block were removed with that block: " result.sourceIdsRemovedWithMapping)
        Log("Wrote " outPath " (" result.bytes.Size " bytes). Downloaded file was not changed.")

        if (!doUpload)
            return

        Log(form.Disposition)
        if (AuthorizationHeader(form.Username, form.Password) != "")
            Log("Authorization: Basic (set)")
        else
            Log("Authorization: (none)")
        response := PostImport(form, result.bytes)
        Log("HTTP " response.status " " response.statusText)
        if (response.finalUrl != "")
            Log("Final URL: " response.finalUrl)
        if (response.body != "")
            Log(response.body)
        if (response.status >= 200 && response.status < 300)
            MsgBox("Upload finished with HTTP " response.status ".", "QAM XML Import", "Iconi")
        else
            MsgBox("Upload returned HTTP " response.status ". The log has the response.", "QAM XML Import", "Icon!")
    } catch as err {
        detail := err.Message
        if (err.Line)
            Log("Error (line " err.Line "): " detail)
        else
            Log("Error: " detail)
        MsgBox(detail, "QAM XML Import", "Icon!")
    } finally {
        SetBusy(false)
    }
}

SetBusy(busy) {
    global Ui
    names := ["SourceId", "Url", "Username", "Password", "UnitLow", "UnitMid", "UnitHigh", "Replacement", "DownloadBtn", "RewriteBtn", "UploadBtn"]
    for name in names {
        ctrl := Ui.%name%
        if (IsObject(ctrl))
            ctrl.Enabled := !busy
    }
}

CollectForm() {
    global Ui
    return {
        XmlPath: DownloadPath(),
        SourceId: Trim(Ui.SourceId.Value),
        UploadName: UPLOAD_NAME,
        Url: Trim(Ui.Url.Value),
        Username: CleanCredential(Ui.Username.Value, true),
        Password: CleanCredential(Ui.Password.Value, false),
        Unit: SelectedUnit(),
        PartType: DEFAULT_PART_TYPE,
        IgnoreTls: true,
        Replacement: ToEditNewlines(Ui.Replacement.Value),
        Disposition: ""
    }
}

ValidateReady(form, doUpload) {
    if !FileExist(form.XmlPath)
        throw Error("Download the XML first. Not found: " form.XmlPath)
    if (form.Replacement == "")
        throw Error("The mapping replacement text is empty. Fill in a Program # for at least one set in the selected unit that has a virtual channel.")

    form.UploadName := SanitizeFilename(form.UploadName)
    form.Disposition := Format("Content-Disposition: form-data; name=`"{1}`"; filename=`"{2}`"", FORM_FIELD, form.UploadName)
    ValidateSourceId(form.SourceId)
    if (doUpload)
        ValidateUpload(form)
    return form
}

ValidateUpload(form) {
    if (form.Url == "")
        throw Error("Enter the upload URL.")
    if !RegExMatch(form.Url, "i)^https?://")
        throw Error("The upload URL must start with http:// or https://.")
}

ValidateSourceId(id) {
    if !RegExMatch(id, "^\d+$")
        throw Error("Source ID must be a number, with digits only.")
    return id
}

Log(msg) {
    global Ui
    if !Ui.HasProp("Log")
        return
    Ui.Log.Value .= (Ui.Log.Value == "" ? "" : "`r`n") . msg
    SendMessage(0x115, 7, 0, Ui.Log.Hwnd) ; WM_VSCROLL / SB_BOTTOM
}

; ---------------------------------------------------------------- rewrite

RewriteXml(fileBuf, replacementText, newSourceId) {
    found := FindOpeningTag(fileBuf)
    enc := found.encoding
    openAt := found.openAt
    openPat := found.openPat
    closePat := EncodeAscii(CLOSE_TAG, enc)
    searchFrom := openAt + openPat.Size
    closeAt := LastIndexOfBytes(fileBuf, searchFrom, fileBuf.Size, closePat)
    if (closeAt < 0)
        throw Error("Could not find </QAM_Mapping> after <QAM_Mapping view=`"Mappings`">.")

    blockEnd := closeAt + closePat.Size
    removed := Slice(fileBuf, openAt, blockEnd)
    removedIds := CountSourceIds(removed, enc)
    replPat := EncodePayload(replacementText, enc)
    spliced := Concat(
        Slice(fileBuf, 0, openAt),
        replPat,
        Slice(fileBuf, blockEnd, fileBuf.Size))
    ids := ReplaceAllSourceIds(spliced, enc, newSourceId)
    return {
        bytes: ids.bytes,
        encoding: enc,
        sourceIdsReplaced: ids.sourceIdsReplaced,
        sourceIdsWithoutNumber: ids.sourceIdsWithoutNumber,
        sourceIdsRemovedWithMapping: removedIds,
        bytesRemoved: removed.Size,
        replacementBytes: replPat.Size,
        mappingStart: openAt,
        mappingEnd: blockEnd
    }
}

FindOpeningTag(buf) {
    order := []
    detected := DetectEncoding(buf)
    if (detected != "")
        order.Push(detected)
    for enc in ["utf-8", "cp1252", "iso-8859-1", "us-ascii", "unknown", "utf-16le", "utf-16be"]
        order.Push(enc)

    seen := Map()
    for enc in order {
        if (seen.Has(enc))
            continue
        seen[enc] := true
        pat := EncodeAscii(OPEN_TAG, enc)
        at := IndexOfBytes(buf, 0, buf.Size, pat)
        if (at >= 0)
            return {encoding: enc, openAt: at, openPat: pat}
    }
    throw Error("Could not find <QAM_Mapping view=`"Mappings`"> in the file.")
}

DetectEncoding(buf) {
    if (StartsWith(buf, [0xFF, 0xFE]))
        return DeclOrDefault(buf, "utf-16le")
    if (StartsWith(buf, [0xFE, 0xFF]))
        return DeclOrDefault(buf, "utf-16be")

    declared := DeclaredEncoding(LatinPrefix(buf, 480))
    if (declared != "")
        return declared
    if (LooksLikeUtf16(buf, "utf-16le"))
        return DeclOrDefault(buf, "utf-16le")
    if (LooksLikeUtf16(buf, "utf-16be"))
        return DeclOrDefault(buf, "utf-16be")
    return "utf-8"
}

DeclOrDefault(buf, fallback) {
    declared := DeclaredEncoding(Utf16Prefix(buf, fallback, 400))
    ; The BOM or the wide tag bytes decide the width. A declaration that
    ; names the other endian, or a single-byte encoding, is not followed.
    if (fallback == "utf-16le" || fallback == "utf-16be") {
        if (declared == "unknown")
            return "unknown"
        return fallback
    }
    if (declared != "")
        return declared
    return fallback
}

DeclaredEncoding(head) {
    if !RegExMatch(head, "i)encoding\s*=\s*[`"']([^`"']+)", &m)
        return ""
    enc := NormalizeEncoding(m[1])
    return enc == "" ? "unknown" : enc
}

NormalizeEncoding(name) {
    n := StrLower(Trim(name))
    n := StrReplace(n, "_", "-")
    n := StrReplace(n, " ", "")
    if (n == "utf-8" || n == "utf8")
        return "utf-8"
    if (n == "utf-16" || n == "utf-16le" || n == "utf16" || n == "unicode")
        return "utf-16le"
    if (n == "utf-16be" || n == "utf16be")
        return "utf-16be"
    if (n == "windows-1252" || n == "cp1252")
        return "cp1252"
    if (n == "iso-8859-1" || n == "iso8859-1" || n == "latin1" || n == "latin-1" || n == "cp28591")
        return "iso-8859-1"
    if (n == "us-ascii" || n == "ascii")
        return "us-ascii"
    return ""
}

LooksLikeUtf16(buf, enc) {
    if (buf.Size < 12)
        return false
    limit := Min(buf.Size, 512)
    xml := EncodeAscii("<?xml", enc)
    tag := EncodeAscii("<QAM_Mapping", enc)
    return IndexOfBytes(buf, 0, limit, xml) >= 0 || IndexOfBytes(buf, 0, limit, tag) >= 0
}

LatinPrefix(buf, maxBytes) {
    n := Min(buf.Size, maxBytes)
    chars := ""
    loop n {
        c := NumGet(buf, A_Index - 1, "UChar")
        if (c == 0)
            break
        chars .= (c > 127) ? "?" : Chr(c)
    }
    return chars
}

Utf16Prefix(buf, enc, maxChars) {
    i := 0
    if (enc == "utf-16le" && StartsWith(buf, [0xFF, 0xFE]))
        i := 2
    else if (enc == "utf-16be" && StartsWith(buf, [0xFE, 0xFF]))
        i := 2
    chars := ""
    count := 0
    while (i + 1 < buf.Size && count < maxChars) {
        b0 := NumGet(buf, i, "UChar")
        b1 := NumGet(buf, i + 1, "UChar")
        code := (enc == "utf-16be") ? ((b0 << 8) | b1) : (b0 | (b1 << 8))
        if (code == 0)
            break
        chars .= (code > 127) ? "?" : Chr(code)
        i += 2
        count += 1
    }
    return chars
}

ReplaceAllSourceIds(buf, enc, newSourceId) {
    openPat := EncodeAscii(SOURCE_OPEN, enc)
    closePat := EncodeAscii(SOURCE_CLOSE, enc)
    newPat := EncodeAscii(newSourceId, enc)
    chunks := []
    pos := 0
    replaced := 0
    withoutNumber := 0
    while (pos < buf.Size) {
        at := IndexOfBytes(buf, pos, buf.Size, openPat)
        if (at < 0) {
            chunks.Push(Slice(buf, pos, buf.Size))
            break
        }
        innerStart := at + openPat.Size
        closeAt := IndexOfBytes(buf, innerStart, buf.Size, closePat)
        if (closeAt < 0) {
            chunks.Push(Slice(buf, pos, buf.Size))
            break
        }
        run := FindDigitRun(buf, innerStart, closeAt, enc)
        chunks.Push(Slice(buf, pos, innerStart))
        if (run.start >= 0) {
            chunks.Push(Slice(buf, innerStart, run.start))
            chunks.Push(newPat)
            chunks.Push(Slice(buf, run.end, closeAt))
            replaced += 1
        } else {
            chunks.Push(Slice(buf, innerStart, closeAt))
            withoutNumber += 1
        }
        chunks.Push(closePat)
        pos := closeAt + closePat.Size
    }
    return {
        bytes: Concat(chunks*),
        sourceIdsReplaced: replaced,
        sourceIdsWithoutNumber: withoutNumber
    }
}

CountSourceIds(buf, enc) {
    info := ReplaceAllSourceIds(buf, enc, "0")
    return info.sourceIdsReplaced + info.sourceIdsWithoutNumber
}

FindDigitRun(buf, start, end, enc) {
    step := (enc == "utf-16le" || enc == "utf-16be") ? 2 : 1
    i := start
    runStart := -1
    while (i + step <= end) {
        if (IsDigitUnit(buf, i, enc)) {
            if (runStart < 0)
                runStart := i
        } else if (runStart >= 0) {
            return {start: runStart, end: i}
        }
        i += step
    }
    if (runStart >= 0)
        return {start: runStart, end: i}
    return {start: -1, end: -1}
}

IsDigitUnit(buf, i, enc) {
    if (enc == "utf-16le")
        return NumGet(buf, i, "UChar") >= 48 && NumGet(buf, i, "UChar") <= 57 && NumGet(buf, i + 1, "UChar") == 0
    if (enc == "utf-16be")
        return NumGet(buf, i, "UChar") == 0 && NumGet(buf, i + 1, "UChar") >= 48 && NumGet(buf, i + 1, "UChar") <= 57
    c := NumGet(buf, i, "UChar")
    return c >= 48 && c <= 57
}

; ---------------------------------------------------------------- bytes

EncodePayload(text, enc) {
    if (IsAscii(text))
        return EncodeAscii(text, enc)
    if (enc == "unknown" || enc == "us-ascii" || enc == "")
        throw Error("The replacement text has characters outside ASCII, and the XML encoding cannot store them.")
    return EncodeText(text, enc)
}

IsAscii(text) {
    loop StrLen(text) {
        if (Ord(SubStr(text, A_Index, 1)) > 127)
            return false
    }
    return true
}

EncodeAscii(text, enc) {
    n := StrLen(text)
    if (enc == "utf-16le") {
        buf := Buffer(n * 2)
        loop n {
            NumPut("UChar", Ord(SubStr(text, A_Index, 1)), buf, (A_Index - 1) * 2)
            NumPut("UChar", 0, buf, (A_Index - 1) * 2 + 1)
        }
        return buf
    }
    if (enc == "utf-16be") {
        buf := Buffer(n * 2)
        loop n {
            NumPut("UChar", 0, buf, (A_Index - 1) * 2)
            NumPut("UChar", Ord(SubStr(text, A_Index, 1)), buf, (A_Index - 1) * 2 + 1)
        }
        return buf
    }
    buf := Buffer(n)
    loop n
        NumPut("UChar", Ord(SubStr(text, A_Index, 1)), buf, A_Index - 1)
    return buf
}

EncodeText(text, enc) {
    ahkEnc := AhkEncodingName(enc)
    buf := EncodeAhk(text, ahkEnc)
    if !(DecodeAhk(buf, ahkEnc) == text)
        throw Error("The replacement text does not fit the XML encoding (" enc ").")
    return buf
}

AhkEncodingName(enc) {
    if (enc == "utf-8")
        return "UTF-8"
    if (enc == "utf-16le")
        return "UTF-16"
    if (enc == "cp1252")
        return "CP1252"
    if (enc == "iso-8859-1")
        return "CP28591"
    throw Error("Unsupported XML encoding: " enc)
}

EncodeAhk(text, ahkEnc) {
    if (text == "")
        return Buffer(0)
    n := StrPut(text, ahkEnc)
    if (n < 2)
        throw Error("Could not encode text as " ahkEnc ".")
    tmp := Buffer(n, 0)
    StrPut(text, tmp, ahkEnc)
    nullBytes := InStr(ahkEnc, "UTF-16") ? 2 : 1
    content := n - nullBytes
    if (content < 0)
        content := 0
    out := Buffer(content)
    if (content)
        DllCall("RtlMoveMemory", "Ptr", out.Ptr, "Ptr", tmp.Ptr, "UPtr", content)
    return out
}

DecodeAhk(buf, ahkEnc) {
    tmp := Buffer(buf.Size + 2, 0)
    if (buf.Size)
        DllCall("RtlMoveMemory", "Ptr", tmp.Ptr, "Ptr", buf.Ptr, "UPtr", buf.Size)
    return StrGet(tmp.Ptr, ahkEnc)
}

IndexOfBytes(hay, start, end, needle) {
    nLen := needle.Size
    if (nLen = 0 || start < 0 || end > hay.Size || end - start < nLen)
        return -1
    last := end - nLen
    first := NumGet(needle, 0, "UChar")
    i := start
    while (i <= last) {
        if (NumGet(hay, i, "UChar") == first && BytesEqual(hay, i, needle))
            return i
        i++
    }
    return -1
}

LastIndexOfBytes(hay, start, end, needle) {
    nLen := needle.Size
    if (nLen = 0 || start < 0 || end > hay.Size || end - start < nLen)
        return -1
    first := NumGet(needle, 0, "UChar")
    i := end - nLen
    while (i >= start) {
        if (NumGet(hay, i, "UChar") == first && BytesEqual(hay, i, needle))
            return i
        i--
    }
    return -1
}

BytesEqual(hay, offset, needle) {
    loop needle.Size {
        if (NumGet(hay, offset + A_Index - 1, "UChar") != NumGet(needle, A_Index - 1, "UChar"))
            return false
    }
    return true
}

Slice(buf, start, end) {
    if (start < 0 || end > buf.Size || start > end)
        throw Error("Invalid slice " start ".." end " of " buf.Size ".")
    n := end - start
    out := Buffer(n)
    if (n)
        DllCall("RtlMoveMemory", "Ptr", out.Ptr, "Ptr", buf.Ptr + start, "UPtr", n)
    return out
}

Concat(parts*) {
    total := 0
    for part in parts
        total += part.Size
    out := Buffer(total)
    offset := 0
    for part in parts {
        if (part.Size) {
            DllCall("RtlMoveMemory", "Ptr", out.Ptr + offset, "Ptr", part.Ptr, "UPtr", part.Size)
            offset += part.Size
        }
    }
    return out
}

StartsWith(buf, sig) {
    if (Type(sig) == "Buffer") {
        if (buf.Size < sig.Size)
            return false
        return sig.Size == 0 || BytesEqual(buf, 0, sig)
    }
    if (buf.Size < sig.Length)
        return false
    loop sig.Length {
        if (NumGet(buf, A_Index - 1, "UChar") != sig[A_Index])
            return false
    }
    return true
}

ReadRaw(path) {
    f := FileOpen(path, "r")
    buf := Buffer(f.Length)
    if (f.Length) {
        got := f.RawRead(buf)
        if (got != f.Length) {
            f.Close()
            throw Error("Could not read the whole file: " path)
        }
    }
    f.Close()
    return buf
}

WriteRaw(path, buf) {
    f := FileOpen(path, "w")
    if (buf.Size) {
        written := f.RawWrite(buf)
        if (written != buf.Size) {
            f.Close()
            throw Error("Could not write the whole file: " path)
        }
    }
    f.Close()
}

; ---------------------------------------------------------------- upload / download

SanitizeFilename(name) {
    name := Trim(name)
    name := RegExReplace(name, "^.*[\\/]", "")
    name := StrReplace(name, Chr(34), "")
    name := StrReplace(name, "`r", "")
    name := StrReplace(name, "`n", "")
    if (name == "")
        throw Error("The upload filename is empty.")
    return name
}

BuildMultipart(fileBytes, filename, partType) {
    filename := SanitizeFilename(filename)
    boundary := ""
    loop 8 {
        boundary := RandomBoundary()
        if (IndexOfBytes(fileBytes, 0, fileBytes.Size, EncodeAscii(boundary, "utf-8")) < 0)
            break
    }
    disposition := Format("Content-Disposition: form-data; name=`"{1}`"; filename=`"{2}`"", FORM_FIELD, filename)
    head := "--" boundary "`r`n" disposition "`r`n"
    if (partType != "")
        head .= "Content-Type: " partType "`r`n"
    head .= "`r`n"
    tail := "`r`n--" boundary "--`r`n"
    return {
        body: Concat(EncodeAscii(head, "utf-8"), fileBytes, EncodeAscii(tail, "utf-8")),
        boundary: boundary,
        disposition: disposition
    }
}

; TODO: placeholder request body for the download. Replace the part below with
; the multipart fields the device expects for an export/download.
BuildDownloadMultipart() {
    boundary := RandomBoundary()
    disposition := "Content-Disposition: form-data; name=`"Export`""
    text := "--" boundary "`r`n" disposition "`r`n`r`n"
        . "`r`n--" boundary "--`r`n"
    return {
        body: EncodeAscii(text, "utf-8"),
        boundary: boundary,
        disposition: disposition
    }
}

CleanCredential(value, trimEdges) {
    value := StrReplace(value, "`r", "")
    value := StrReplace(value, "`n", "")
    if (trimEdges)
        value := Trim(value, " `t")
    return value
}

; Base64 of the UTF-8 bytes of "username:password", used as:
; Authorization: Basic {Basic64Encode("username:password")}
Basic64Encode(text) {
    data := EncodePayload(text, "utf-8")
    alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    out := ""
    i := 0
    n := data.Size
    while (i < n) {
        b0 := NumGet(data, i, "UChar")
        b1 := (i + 1 < n) ? NumGet(data, i + 1, "UChar") : 0
        b2 := (i + 2 < n) ? NumGet(data, i + 2, "UChar") : 0
        triple := (b0 << 16) | (b1 << 8) | b2
        out .= SubStr(alphabet, ((triple >> 18) & 63) + 1, 1)
        out .= SubStr(alphabet, ((triple >> 12) & 63) + 1, 1)
        if (i + 1 < n)
            out .= SubStr(alphabet, ((triple >> 6) & 63) + 1, 1)
        else
            out .= "="
        if (i + 2 < n)
            out .= SubStr(alphabet, (triple & 63) + 1, 1)
        else
            out .= "="
        i += 3
    }
    return out
}

AuthorizationHeader(username, password) {
    if (username == "" && password == "")
        return ""
    return "Basic " Basic64Encode(username ":" password)
}

RandomBoundary() {
    chars := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    out := "----QamXmlImport"
    loop 24
        out .= SubStr(chars, Random(1, StrLen(chars)), 1)
    return out
}

PostImport(form, fileBytes) {
    packed := BuildMultipart(fileBytes, form.UploadName, form.PartType)
    return SendMultipart(form, packed)
}

SendMultipart(form, packed) {
    whr := ComObject("WinHttp.WinHttpRequest.5.1")
    whr.Open("POST", form.Url, false)
    whr.SetTimeouts(10000, 30000, 120000, 120000)
    if (form.IgnoreTls)
        whr.Option[4] := 0x3300
    try whr.Option[9] := 0x2A00
    catch
        try whr.Option[9] := 0x800
    whr.SetRequestHeader("User-Agent", BROWSER_UA)
    whr.SetRequestHeader("Content-Type", "multipart/form-data; boundary=" packed.boundary)
    auth := AuthorizationHeader(form.Username, form.Password)
    if (auth != "")
        whr.SetRequestHeader("Authorization", auth)
    try
        whr.Send(BufferToSafeArray(packed.body))
    catch as err
        throw Error("Request failed. " err.Message)

    status := 0
    statusText := ""
    bodyText := ""
    bodyBytes := Buffer(0)
    finalUrl := ""
    try {
        status := whr.Status
        statusText := whr.StatusText
    } catch as err {
        throw Error("Request failed. " err.Message)
    }
    try bodyBytes := SafeArrayToBuffer(whr.ResponseBody)
    catch
        bodyBytes := Buffer(0)
    try bodyText := whr.ResponseText
    catch
        bodyText := ""
    try finalUrl := whr.Option[1]
    catch
        finalUrl := ""
    return {
        status: status,
        statusText: statusText,
        body: PreviewText(bodyText, 2000),
        bytes: bodyBytes,
        finalUrl: finalUrl,
        disposition: packed.disposition
    }
}

BufferToSafeArray(buf) {
    arr := ComObjArray(0x11, buf.Size) ; VT_UI1
    if (buf.Size) {
        pv := NumGet(ComObjValue(arr), 8 + A_PtrSize, "Ptr")
        DllCall("RtlMoveMemory", "Ptr", pv, "Ptr", buf.Ptr, "UPtr", buf.Size)
    }
    return arr
}

SafeArrayToBuffer(arr) {
    n := arr.MaxIndex() + 1
    buf := Buffer(n)
    if (n) {
        pv := NumGet(ComObjValue(arr), 8 + A_PtrSize, "Ptr")
        DllCall("RtlMoveMemory", "Ptr", buf.Ptr, "Ptr", pv, "UPtr", n)
    }
    return buf
}

PreviewText(text, max) {
    text := StrReplace(text, "`r", "")
    if (StrLen(text) <= max)
        return text
    return SubStr(text, 1, max) "`n... (truncated)"
}

; ---------------------------------------------------------------- settings

IniPath() {
    return A_ScriptDir "\QamXmlImport.ini"
}

LoadSettings() {
    return {
        SourceId: ReadIni("SourceId", ""),
        Url: ReadIni("Url", ""),
        Username: ReadIni("Username", ""),
        Password: ReadIni("Password", ""),
        Unit: ReadIni("Unit", "Low")
    }
}

ReadIni(key, default) {
    path := IniPath()
    if !FileExist(path)
        return default
    try
        return IniRead(path, "Settings", key, default)
    catch
        return default
}

SaveSettings(form) {
    WriteIni("SourceId", form.SourceId)
    WriteIni("Url", form.Url)
    WriteIni("Username", form.Username)
    WriteIni("Password", form.Password)
    WriteIni("Unit", form.Unit)
}

WriteIni(key, value) {
    path := IniPath()
    if (value == "") {
        try IniDelete(path, "Settings", key)
        catch
            return
        return
    }
    IniWrite(value, path, "Settings", key)
}

NormalizeNewlines(text) {
    text := StrReplace(text, "`r`n", "`n")
    text := StrReplace(text, "`r", "`n")
    return text
}

ToEditNewlines(text) {
    return StrReplace(NormalizeNewlines(text), "`n", "`r`n")
}


; ---------------------------------------------------------------- self-test

RunSelfTest() {
    global Tests
    Tests := {failures: 0}
    try {
        TestBasicSpliceKeepsOutsideBytes()
        TestFirstOpenAndLastClose()
        TestSourceIdWhitespaceAndSkippedText()
        TestLeadingZerosAndInsideMapping()
        TestReplacementSourceIdIsUpdated()
        TestUtf16LeBom()
        TestUtf16BeBom()
        TestWindows1252Declaration()
        TestUtf8ReplacementAndHighByte()
        TestMissingTagsThrow()
        TestMultipartPackaging()
        TestBasicAuthorization()
        TestSourceIdValidation()
        TestRawRoundTrip()
    } catch as err {
        FileAppend("EX line " err.Line ": " err.Message "`n", "*")
        return 1
    }
    if (Tests.failures)
        FileAppend(Tests.failures " failed`n", "*")
    else
        FileAppend("ok`n", "*")
    return Tests.failures ? 1 : 0
}

TestBasicSpliceKeepsOutsideBytes() {
    input := Concat(
        Raw([0xFF, 0x00, 0xFE]),
        Ascii("<note>keep</note><Source_ID>55</Source_ID>"),
        Ascii(OPEN_TAG),
        Ascii("DELETE"),
        Ascii(CLOSE_TAG),
        Raw([0x10, 0x80]),
        Ascii("<Source_ID>7</Source_ID>END"))
    result := RewriteXml(input, "PLACEHOLDER", "99")
    expected := Concat(
        Raw([0xFF, 0x00, 0xFE]),
        Ascii("<note>keep</note><Source_ID>99</Source_ID>"),
        Ascii("PLACEHOLDER"),
        Raw([0x10, 0x80]),
        Ascii("<Source_ID>99</Source_ID>END"))
    AssertBuf(result.bytes, expected, "basic splice")
    AssertTrue(result.sourceIdsReplaced == 2, "basic replaced count")
    AssertTrue(result.encoding == "utf-8", "basic encoding")
}

TestFirstOpenAndLastClose() {
    input := Ascii("PRE</QAM_Mapping>" OPEN_TAG "A" CLOSE_TAG "MID" OPEN_TAG "B" CLOSE_TAG "POST")
    result := RewriteXml(input, "PLACEHOLDER", "1")
    expected := Ascii("PRE</QAM_Mapping>PLACEHOLDERPOST")
    AssertBuf(result.bytes, expected, "first open last close")
}

TestSourceIdWhitespaceAndSkippedText() {
    input := Ascii("<Source_ID>  12  </Source_ID><Source_ID>none</Source_ID>" OPEN_TAG "X" CLOSE_TAG "<Source_ID>-4-</Source_ID>")
    result := RewriteXml(input, "PLACEHOLDER", "34")
    expected := Ascii("<Source_ID>  34  </Source_ID><Source_ID>none</Source_ID>PLACEHOLDER<Source_ID>-34-</Source_ID>")
    AssertBuf(result.bytes, expected, "whitespace and non-digits")
    AssertTrue(result.sourceIdsReplaced == 2, "whitespace replaced count")
    AssertTrue(result.sourceIdsWithoutNumber == 1, "skipped non-digit count")
}

TestLeadingZerosAndInsideMapping() {
    input := Ascii(OPEN_TAG "<Source_ID>5</Source_ID>" CLOSE_TAG "<Source_ID>6</Source_ID>")
    result := RewriteXml(input, "PLACEHOLDER", "007")
    expected := Ascii("PLACEHOLDER<Source_ID>007</Source_ID>")
    AssertBuf(result.bytes, expected, "leading zeros")
    AssertTrue(result.sourceIdsRemovedWithMapping == 1, "removed with mapping")
    AssertTrue(result.sourceIdsReplaced == 1, "outside id replaced")
}

TestReplacementSourceIdIsUpdated() {
    input := Ascii("<Source_ID>2</Source_ID>" OPEN_TAG "OLD" CLOSE_TAG)
    result := RewriteXml(input, "X<Source_ID>1</Source_ID>Y", "9")
    expected := Ascii("<Source_ID>9</Source_ID>X<Source_ID>9</Source_ID>Y")
    AssertBuf(result.bytes, expected, "replacement source id")
}

TestUtf16LeBom() {
    payload := "<Source_ID>5</Source_ID>" OPEN_TAG "ZZ" CLOSE_TAG "OK"
    expectedText := "<Source_ID>123</Source_ID>PLACEHOLDEROK"
    input := Concat(Raw([0xFF, 0xFE]), EncodeAscii(payload, "utf-16le"))
    result := RewriteXml(input, "PLACEHOLDER", "123")
    expected := Concat(Raw([0xFF, 0xFE]), EncodeAscii(expectedText, "utf-16le"))
    AssertBuf(result.bytes, expected, "utf-16 le")
    AssertTrue(result.encoding == "utf-16le", "utf-16 encoding name")
    AssertTrue(result.sourceIdsReplaced == 1, "utf-16 replaced count")
}

TestUtf16BeBom() {
    payload := "<Source_ID>5</Source_ID>" OPEN_TAG "ZZ" CLOSE_TAG "OK"
    expectedText := "<Source_ID>123</Source_ID>PLACEHOLDEROK"
    input := Concat(Raw([0xFE, 0xFF]), EncodeAscii(payload, "utf-16be"))
    result := RewriteXml(input, "PLACEHOLDER", "123")
    expected := Concat(Raw([0xFE, 0xFF]), EncodeAscii(expectedText, "utf-16be"))
    AssertBuf(result.bytes, expected, "utf-16 be")
    AssertTrue(result.encoding == "utf-16be", "utf-16 be name")
}

TestWindows1252Declaration() {
    input := Concat(
        Ascii("<?xml version=`"1.0`" encoding=`"windows-1252`"?>"),
        Raw([0x93]),
        Ascii("<Source_ID>1</Source_ID>" OPEN_TAG "OLD" CLOSE_TAG))
    result := RewriteXml(input, "PLACEHOLDER", "2")
    expected := Concat(
        Ascii("<?xml version=`"1.0`" encoding=`"windows-1252`"?>"),
        Raw([0x93]),
        Ascii("<Source_ID>2</Source_ID>PLACEHOLDER"))
    AssertBuf(result.bytes, expected, "windows-1252 bytes")
    AssertTrue(result.encoding == "cp1252", "windows-1252 name")
}

TestUtf8ReplacementAndHighByte() {
    input := Concat(
        Ascii("<?xml encoding=`"UTF-8`"?>" OPEN_TAG "OLD" CLOSE_TAG),
        Raw([0x80]))
    result := RewriteXml(input, Chr(0xE9), "1")
    expected := Concat(
        Ascii("<?xml encoding=`"UTF-8`"?>"),
        Raw([0xC3, 0xA9]),
        Raw([0x80]))
    AssertBuf(result.bytes, expected, "utf-8 e-acute")
    AssertTrue(result.encoding == "utf-8", "utf-8 name")
}

TestMissingTagsThrow() {
    AssertThrows("missing open", (*) => RewriteXml(Ascii("<root></root>"), "PLACEHOLDER", "1"), "Could not find")
    AssertThrows("missing close", (*) => RewriteXml(Ascii(OPEN_TAG "no close"), "PLACEHOLDER", "1"), "Could not find")
}

TestMultipartPackaging() {
    fileBytes := Concat(Ascii("AB"), Raw([0xFF]), Ascii("CD"))
    packed := BuildMultipart(fileBytes, "C:\temp\my`"file.xml", "text/xml")
    AssertTrue(packed.disposition == "Content-Disposition: form-data; name=`"Import`"; filename=`"myfile.xml`"", "disposition text")
    dispAt := 2 + StrLen(packed.boundary) + 2
    dispBytes := EncodeAscii(packed.disposition "`r`n", "utf-8")
    AssertBuf(Slice(packed.body, dispAt, dispAt + dispBytes.Size), dispBytes, "disposition bytes")
    AssertTrue(StartsWith(packed.body, BytesOf("--" packed.boundary "`r`n")), "body starts with boundary")

    blankAt := IndexOfBytes(packed.body, 0, packed.body.Size, EncodeAscii("`r`n`r`n", "utf-8"))
    closeNeedle := EncodeAscii("`r`n--" packed.boundary "--`r`n", "utf-8")
    closeAt := LastIndexOfBytes(packed.body, 0, packed.body.Size, closeNeedle)
    AssertTrue(blankAt >= 0 && closeAt > blankAt, "multipart framing")
    AssertBuf(Slice(packed.body, blankAt + 4, closeAt), fileBytes, "multipart file bytes")
    AssertTrue(IndexOfBytes(packed.body, 0, packed.body.Size, EncodeAscii("Content-Type: text/xml`r`n", "utf-8")) > 0, "part content type")

    bare := BuildMultipart(fileBytes, "plain.xml", "")
    AssertTrue(IndexOfBytes(bare.body, 0, bare.body.Size, EncodeAscii("Content-Type:", "utf-8")) < 0, "omitted part content type")
    AssertTrue(InStr(bare.disposition, "filename=`"plain.xml`"") > 0, "plain filename")
    spaced := BuildMultipart(fileBytes, "my file.xml", "text/xml")
    AssertTrue(spaced.disposition == "Content-Disposition: form-data; name=`"Import`"; filename=`"my file.xml`"", "spaced filename")
}

TestRawRoundTrip() {
    path := A_Temp "\qam-xml-import-selftest.bin"
    input := Concat(Ascii(OPEN_TAG "OLD" CLOSE_TAG "<Source_ID>4</Source_ID>"), Raw([0xFF, 0x00]))
    WriteRaw(path, input)
    loaded := ReadRaw(path)
    try FileDelete(path)
    AssertBuf(loaded, input, "raw readback")
    result := RewriteXml(loaded, "PLACEHOLDER", "8")
    expected := Concat(Ascii("PLACEHOLDER<Source_ID>8</Source_ID>"), Raw([0xFF, 0x00]))
    AssertBuf(result.bytes, expected, "raw round trip")
}

TestBasicAuthorization() {
    AssertTrue(Basic64Encode("f") == "Zg==", "base64 one byte")
    AssertTrue(Basic64Encode("fo") == "Zm8=", "base64 two bytes")
    AssertTrue(Basic64Encode("foo") == "Zm9v", "base64 three bytes")
    AssertTrue(Basic64Encode("username:password") == "dXNlcm5hbWU6cGFzc3dvcmQ=", "base64 username:password")
    AssertTrue(Basic64Encode(Chr(0xE9) ":" Chr(0xE9)) == "w6k6w6k=", "base64 utf-8 credentials")
    AssertTrue(AuthorizationHeader("", "") == "", "blank authorization omitted")
    AssertTrue(AuthorizationHeader("username", "password") == "Basic dXNlcm5hbWU6cGFzc3dvcmQ=", "authorization header")
    AssertTrue(AuthorizationHeader("", "password") == "Basic OnBhc3N3b3Jk", "password only")
}

TestSourceIdValidation() {
    AssertTrue(ValidateSourceId("007") == "007", "accept leading zeros")
    AssertThrows("reject letters", (*) => ValidateSourceId("12a"), "digits only")
    AssertThrows("reject empty", (*) => ValidateSourceId(""), "digits only")
}

Ascii(text) {
    return EncodeAscii(text, "utf-8")
}

BytesOf(text) {
    return EncodeAscii(text, "utf-8")
}

Raw(values) {
    buf := Buffer(values.Length)
    loop values.Length
        NumPut("UChar", values[A_Index], buf, A_Index - 1)
    return buf
}

AssertBuf(actual, expected, label) {
    global Tests
    if (actual.Size == expected.Size && (actual.Size == 0 || BytesEqual(actual, 0, expected)))
        return
    Tests.failures += 1
    FileAppend("FAIL " label "`n actual " actual.Size " " HexPreview(actual) "`n expect " expected.Size " " HexPreview(expected) "`n", "*")
}

AssertTrue(cond, label) {
    global Tests
    if (cond)
        return
    Tests.failures += 1
    FileAppend("FAIL " label "`n", "*")
}

AssertThrows(label, fn, needle) {
    global Tests
    try
        fn.Call()
    catch as err {
        if (needle != "" && !InStr(err.Message, needle)) {
            Tests.failures += 1
            FileAppend("FAIL " label " threw: " err.Message "`n", "*")
        }
        return
    }
    Tests.failures += 1
    FileAppend("FAIL " label " did not throw`n", "*")
}

HexPreview(buf) {
    n := Min(buf.Size, 96)
    out := ""
    loop n
        out .= Format("{:02X}", NumGet(buf, A_Index - 1, "UChar"))
    if (buf.Size > n)
        out .= "..."
    return out
}
