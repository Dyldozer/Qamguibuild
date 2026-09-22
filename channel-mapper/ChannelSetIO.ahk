; ChannelSetIO.ahk - Save/Load functionality for Channel Assignment Sets
; Include this file in main GUI scripts

SaveChannelSets(*) {
    global ChannelSets
    
    ; Prompt for save location
    savePath := FileSelect("S16", A_ScriptDir "\ChannelAssignments.txt", "Save Channel Assignments", "Text Files (*.txt)")
    
    if (savePath = "")
        return
    
    ; Ensure .txt extension
    if !RegExMatch(savePath, "i)\.txt$")
        savePath .= ".txt"
    
    ; Build save content
    content := ""
    for set in ChannelSets {
        if (set.HasOwnProp("NameEdit") && set.HasOwnProp("ProgramEdit")) {
            name := set.NameEdit.Value
            progNum := set.ProgramEdit.Value
            vChannel := set.VirtualChannel
            
            ; Only save sets that have data
            if (name != "" || progNum != "") {
                content .= "Set" set.Index "=" name "|" progNum "|" vChannel "`n"
            }
        }
    }
    
    if (content = "") {
        MsgBox("No channel assignments to save.", "Save", "Icon!")
        return
    }
    
    ; Delete existing file if present
    if FileExist(savePath)
        FileDelete(savePath)
    
    ; Write to file
    try {
        FileAppend(content, savePath)
        MsgBox("Saved " CountLines(content) " channel assignments to:`n" savePath, "Save Complete", "Iconi")
    } catch as e {
        MsgBox("Error saving file: " e.Message, "Save Error", "Icon!")
    }
}

LoadChannelSets(*) {
    global ChannelSets
    
    ; Prompt for file to load
    loadPath := FileSelect(1, A_ScriptDir, "Load Channel Assignments", "Text Files (*.txt)")
    
    if (loadPath = "")
        return
    
    if !FileExist(loadPath) {
        MsgBox("File not found: " loadPath, "Load Error", "Icon!")
        return
    }
    
    ; Read file content
    try {
        content := FileRead(loadPath)
    } catch as e {
        MsgBox("Error reading file: " e.Message, "Load Error", "Icon!")
        return
    }
    
    ; Parse and load each line
    loadedCount := 0
    Loop Parse, content, "`n", "`r" {
        line := Trim(A_LoopField)
        if (line = "")
            continue
        
        ; Parse: Set1=Name|ProgramNum|VirtualChannel
        if RegExMatch(line, "i)^Set(\d+)=(.*)$", &match) {
            setIndex := Integer(match[1])
            values := StrSplit(match[2], "|")
            
            if (values.Length >= 2) {
                name := values[1]
                progNum := values[2]
                
                ; Find the matching set and update its edit boxes
                for set in ChannelSets {
                    if (set.Index = setIndex && set.HasOwnProp("NameEdit") && set.HasOwnProp("ProgramEdit")) {
                        set.NameEdit.Value := name
                        set.ProgramEdit.Value := progNum
                        loadedCount++
                        break
                    }
                }
            }
        }
    }
    
    MsgBox("Loaded " loadedCount " channel assignments from:`n" loadPath, "Load Complete", "Iconi")
}

ClearAllChannelSets(*) {
    global ChannelSets
    
    result := MsgBox("Clear all channel assignments?", "Confirm Clear", "YesNo Icon?")
    if (result != "Yes")
        return
    
    for set in ChannelSets {
        if (set.HasOwnProp("NameEdit") && set.HasOwnProp("ProgramEdit")) {
            set.NameEdit.Value := ""
            set.ProgramEdit.Value := ""
        }
    }
    
    MsgBox("All channel assignments cleared.", "Clear Complete", "Iconi")
}

CountLines(str) {
    count := 0
    Loop Parse, str, "`n", "`r" {
        if (Trim(A_LoopField) != "")
            count++
    }
    return count
}

; Right-click handler for ListView - copies Name column to clipboard
SetupListViewRightClick(lv) {
    lv.OnEvent("ContextMenu", OnListViewRightClick)
}

OnListViewRightClick(LV, rowNum, isRightClick, x, y) {
    if (rowNum = 0)
        return
    
    ; Get the name from column 3
    name := LV.GetText(rowNum, 3)
    
    if (name != "") {
        A_Clipboard := name
        ToolTip("Copied: " name)
        SetTimer(ClearToolTip, -1500)
    }
}

ClearToolTip() {
    ToolTip()
}
