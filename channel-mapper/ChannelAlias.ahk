; ChannelAlias.ahk - Edit set config (name, virtual channel, aliases) and
; fuzzy-match loaded channels against those aliases.
; Included by ChannelMapper.ahk and ChannelMapper_Standalone.ahk.

; A suggestion is shown when its score is at least this high (0-100).
global AliasMatchShowThreshold := 67
; Empty sets at or above this score start checked in the suggestion window.
global AliasMatchCheckThreshold := 94

global SuggestionGui := ""
global SuggestionLV := ""
global SuggestionRows := []

global ConfigGui := ""
global ConfigLV := ""
global ConfigDraft := []
global ConfigCurrentRow := 0
global ConfigLoading := false
global ConfigNameEdit := ""
global ConfigVchEdit := ""
global ConfigAliasEdit := ""

; ---------------------------------------------------------------------------
; Config file values
; ---------------------------------------------------------------------------

ParseAliasList(raw) {
    aliases := []
    seen := Map()
    if (raw = "")
        return aliases

    parts := StrSplit(raw, "|`n`r")
    for part in parts {
        alias := Trim(part)
        if (alias = "")
            continue
        key := StrLower(alias)
        if (seen.Has(key))
            continue
        seen[key] := true
        aliases.Push(alias)
    }
    return aliases
}

CloneAliasList(aliases) {
    copy := []
    if (!IsObject(aliases))
        return copy
    for alias in aliases
        copy.Push(alias)
    return copy
}

CleanIniValue(value) {
    value := StrReplace(value, "`r", " ")
    value := StrReplace(value, "`n", " ")
    return Trim(value)
}

FormatAliasList(aliases) {
    cleaned := []
    seen := Map()
    for alias in aliases {
        text := CleanIniValue(StrReplace(alias, "|", " "))
        if (text = "")
            continue
        key := StrLower(text)
        if (seen.Has(key))
            continue
        seen[key] := true
        cleaned.Push(text)
    }
    return JoinWith(cleaned, "|")
}

FormatAliasDisplay(aliases) {
    return JoinWith(aliases, ", ")
}

JoinWith(items, separator) {
    out := ""
    for item in items {
        if (out != "")
            out .= separator
        out .= item
    }
    return out
}

DisplayLabel(name, index) {
    if (name = "")
        return "Set " index
    ; Static text treats a single & as an accelerator marker.
    return StrReplace(name, "&", "&&")
}

; ---------------------------------------------------------------------------
; Fuzzy matching
; ---------------------------------------------------------------------------

NormalizeChannelName(str) {
    str := StrLower(Trim(str))
    if (str = "")
        return ""
    str := StrReplace(str, "&", " and ")
    str := RegExReplace(str, "[^a-z0-9]+", " ")
    str := Trim(RegExReplace(str, " +", " "))
    if (StrLen(str) > 4 && SubStr(str, 1, 4) = "the ")
        str := Trim(SubStr(str, 5))
    return str
}

QualifierMap() {
    static quals := Map(
        "hd", 1, "sd", 1, "fhd", 1, "uhd", 1, "4k", 1, "hdr", 1,
        "east", 1, "west", 1, "pacific", 1, "central", 1, "mountain", 1,
        "dtv", 1, "hevc", 1, "tv", 1)
    return quals
}

; Quality words can sit at the front ("HD Nick") as well as the end.
LeadingQualityMap() {
    static quals := Map("hd", 1, "sd", 1, "fhd", 1, "uhd", 1, "4k", 1, "hdr", 1)
    return quals
}

StripEdgeQualifiers(str) {
    if (str = "")
        return ""

    quals := QualifierMap()
    leading := LeadingQualityMap()
    loop {
        tokens := StrSplit(str, " ")
        changed := false
        while (tokens.Length > 1 && quals.Has(tokens[tokens.Length])) {
            tokens.Pop()
            changed := true
        }
        while (tokens.Length > 1 && leading.Has(tokens[1])) {
            tokens.RemoveAt(1)
            changed := true
        }
        if (!changed)
            break
        str := JoinWith(tokens, " ")
    }
    return str
}

; ESPN / ESPN2 and "News 5" / "News 7" are different stations, not typos.
DifferByStationNumber(a, b) {
    if (a = b)
        return false
    return SameStemDifferentNumber(a, b) || SameStemDifferentNumber(b, a)
}

SameStemDifferentNumber(longer, shorter) {
    if (RegExMatch(longer, "^(.*?)(\d+)$", &m)) {
        stem := Trim(m[1])
        if (stem != "" && stem = shorter)
            return true
    }
    if (RegExMatch(longer, "^(.+)\s+(\d+)$", &m)) {
        stem := Trim(m[1])
        if (stem != "" && stem = shorter)
            return true
    }
    if (RegExMatch(longer, "^(.+?)(\d+)$", &ml) && RegExMatch(shorter, "^(.+?)(\d+)$", &ms)) {
        if (Trim(ml[1]) != "" && Trim(ml[1]) = Trim(ms[1]) && ml[2] != ms[2])
            return true
    }
    if (RegExMatch(longer, "^(.+)\s+(\d+)$", &ml) && RegExMatch(shorter, "^(.+)\s+(\d+)$", &ms)) {
        if (Trim(ml[1]) = Trim(ms[1]) && ml[2] != ms[2])
            return true
    }
    return false
}

Levenshtein(a, b) {
    aLen := StrLen(a)
    bLen := StrLen(b)
    if (aLen = 0)
        return bLen
    if (bLen = 0)
        return aLen

    prev := []
    Loop bLen + 1
        prev.Push(A_Index - 1)

    Loop aLen {
        i := A_Index
        curr := []
        curr.Push(i)
        ca := SubStr(a, i, 1)
        Loop bLen {
            j := A_Index
            cb := SubStr(b, j, 1)
            cost := (ca = cb) ? 0 : 1
            del := prev[j + 1] + 1
            ins := curr[j] + 1
            sub := prev[j] + cost
            curr.Push(Min(del, ins, sub))
        }
        prev := curr
    }
    return prev[bLen + 1]
}

CountTokenOverlap(source, target) {
    used := Map()
    count := 0
    for token in source {
        for j, other in target {
            if (other = token && !used.Has(j)) {
                used[j] := true
                count++
                break
            }
        }
    }
    return count
}

TokenCharLength(tokens) {
    total := 0
    for token in tokens
        total += StrLen(token)
    return total
}

; Words that show up on many unrelated channels. They cannot be the only
; reason for a high-confidence match, so "network" does not match both
; "Paramount Network" and "Cartoon Network".
GenericChannelWord(token) {
    static words := Map("network", 1, "channel", 1)
    return words.Has(token)
}

HasDistinctiveToken(tokens) {
    for token in tokens {
        if (!GenericChannelWord(token))
            return true
    }
    return false
}

; True when every alias word appears as its own word in the channel name,
; and the alias includes a word that identifies the station.
AliasContainedInChannel(aliasCore, channelCore) {
    aliasTokens := StrSplit(aliasCore, " ")
    channelTokens := StrSplit(channelCore, " ")
    if (aliasTokens.Length = 0 || channelTokens.Length = 0)
        return false
    if (TokenCharLength(aliasTokens) < 3)
        return false
    if (!HasDistinctiveToken(aliasTokens))
        return false
    return CountTokenOverlap(aliasTokens, channelTokens) = aliasTokens.Length
}

TokenCoverageScore(a, b) {
    at := StrSplit(a, " ")
    bt := StrSplit(b, " ")
    if (at.Length = 0 || bt.Length = 0 || a = "" || b = "")
        return 0

    if (at.Length <= bt.Length) {
        short := at
        long := bt
    } else {
        short := bt
        long := at
    }

    inter := CountTokenOverlap(short, long)
    if (inter = short.Length && TokenCharLength(short) >= 3 && long.Length > 0) {
        ; "network" inside "Paramount Network" is not a partial match worth showing.
        if (!HasDistinctiveToken(short))
            return 0
        return Round(100 * short.Length / long.Length)
    }

    union := at.Length + bt.Length - CountTokenOverlap(at, bt)
    if (union = 0)
        return 0
    return Round(100 * CountTokenOverlap(at, bt) / union)
}

; 100 exact, 96 when the alias words are all in the channel name (so "nick"
; matches "HD Nick BB") or the names match once HD/region/TV wording is
; ignored. 0 when the only difference is a station number.
ScoreAliasMatch(channelName, alias) {
    channelNorm := NormalizeChannelName(channelName)
    aliasNorm := NormalizeChannelName(alias)
    if (channelNorm = "" || aliasNorm = "")
        return 0
    if (channelNorm = aliasNorm)
        return 100

    channelCore := StripEdgeQualifiers(channelNorm)
    aliasCore := StripEdgeQualifiers(aliasNorm)
    if (channelCore = "" || aliasCore = "")
        return 0
    if (channelCore = aliasCore)
        return 96
    if (DifferByStationNumber(channelCore, aliasCore))
        return 0
    ; "nick" is a whole word in "HD Nick BB". Extra words do not reject it.
    if (AliasContainedInChannel(aliasCore, channelCore))
        return 96

    score := TokenCoverageScore(channelCore, aliasCore)

    cLen := StrLen(channelCore)
    aLen := StrLen(aliasCore)
    maxLen := Max(cLen, aLen)
    minLen := Min(cLen, aLen)
    if (minLen >= 4 && maxLen <= 48 && minLen / maxLen >= 0.6) {
        dist := Levenshtein(channelCore, aliasCore)
        levScore := Round(100 * (1 - (dist / maxLen)))
        if (levScore > score)
            score := levScore
    }
    return score
}

CollectSetAliases(set) {
    found := []
    seen := Map()
    names := []

    if (set.HasOwnProp("DefaultName") && set.DefaultName != "")
        names.Push(set.DefaultName)
    if (set.HasOwnProp("Aliases") && IsObject(set.Aliases)) {
        for alias in set.Aliases
            names.Push(alias)
    }

    for name in names {
        key := NormalizeChannelName(name)
        if (key = "" || seen.Has(key))
            continue
        seen[key] := true
        found.Push(name)
    }
    return found
}

GetVisibleChannels() {
    global LV
    channels := []
    if (!IsObject(LV))
        return channels

    count := LV.GetCount()
    Loop count {
        name := LV.GetText(A_Index, 3)
        if (name = "")
            continue
        channel := {}
        channel.Channel := LV.GetText(A_Index, 1)
        channel.ProgramNum := LV.GetText(A_Index, 2)
        channel.Name := name
        channel.Frequency := LV.GetText(A_Index, 4)
        channels.Push(channel)
    }
    return channels
}

SafeProgramNum(value) {
    if (value = "" || !RegExMatch(value, "^\d+$"))
        return 999999
    return Integer(value)
}

BuildAliasSuggestions(channels) {
    global ChannelSets, AliasMatchShowThreshold

    suggestions := []
    for set in ChannelSets {
        aliases := CollectSetAliases(set)
        if (aliases.Length = 0)
            continue
        if (!set.HasOwnProp("NameEdit") || !set.HasOwnProp("ProgramEdit"))
            continue

        bestScore := -1
        bestChannel := ""
        bestAlias := ""
        for alias in aliases {
            for channel in channels {
                score := ScoreAliasMatch(channel.Name, alias)
                if (score < AliasMatchShowThreshold)
                    continue
                better := false
                if (score > bestScore)
                    better := true
                else if (score = bestScore && IsObject(bestChannel) && SafeProgramNum(channel.ProgramNum) < SafeProgramNum(bestChannel.ProgramNum))
                    better := true
                if (better) {
                    bestScore := score
                    bestChannel := channel
                    bestAlias := alias
                }
            }
        }

        if (!IsObject(bestChannel))
            continue

        suggestion := {}
        suggestion.SetIndex := set.Index
        suggestion.SetName := (set.DefaultName != "") ? set.DefaultName : "Set " set.Index
        suggestion.VirtualChannel := set.VirtualChannel
        suggestion.ChannelName := bestChannel.Name
        suggestion.ProgramNum := bestChannel.ProgramNum
        suggestion.MatchedAlias := bestAlias
        suggestion.Score := bestScore
        suggestion.CurrentName := set.NameEdit.Value
        suggestion.CurrentProgram := set.ProgramEdit.Value
        suggestion.Shared := 0
        suggestions.Push(suggestion)
    }

    MarkSharedSuggestions(suggestions)
    SortSuggestions(suggestions)
    return suggestions
}

MarkSharedSuggestions(suggestions) {
    counts := Map()
    for suggestion in suggestions {
        key := suggestion.ProgramNum "|" suggestion.ChannelName
        if (counts.Has(key))
            counts[key] := counts[key] + 1
        else
            counts[key] := 1
    }
    for suggestion in suggestions {
        key := suggestion.ProgramNum "|" suggestion.ChannelName
        if (counts[key] > 1)
            suggestion.Shared := 1
    }
}

SortSuggestions(items) {
    n := items.Length
    if (n < 2)
        return

    Loop n - 1 {
        i := A_Index + 1
        current := items[i]
        j := i - 1
        while (j >= 1 && SuggestionComesFirst(current, items[j])) {
            items[j + 1] := items[j]
            j--
        }
        items[j + 1] := current
    }
}

SuggestionComesFirst(a, b) {
    if (a.Score != b.Score)
        return a.Score > b.Score
    return a.SetIndex < b.SetIndex
}

ShouldPrecheckSuggestion(suggestion) {
    global AliasMatchCheckThreshold
    if (suggestion.Shared)
        return false
    if (suggestion.CurrentName != "" || suggestion.CurrentProgram != "")
        return false
    return suggestion.Score >= AliasMatchCheckThreshold
}

SuggestionStatus(suggestion) {
    if (suggestion.CurrentName = "" && suggestion.CurrentProgram = "")
        status := "Empty"
    else if (suggestion.CurrentName = suggestion.ChannelName && suggestion.CurrentProgram = suggestion.ProgramNum)
        status := "Already assigned"
    else
        status := "Replace " suggestion.CurrentName

    if (suggestion.Shared)
        status .= " - also suggested for another set"
    return status
}

SuggestAliasMatches(*) {
    global ChannelSets, SearchEdit

    channels := GetVisibleChannels()
    if (channels.Length = 0) {
        MsgBox("Load channels before matching aliases.`n`nThe channel list is empty.", "Match Aliases", "Icon!")
        return
    }

    configured := 0
    for set in ChannelSets {
        if (CollectSetAliases(set).Length > 0)
            configured++
    }
    if (configured = 0) {
        MsgBox("No set names or aliases are configured yet.`n`nUse Edit Config to set a name and aliases for each channel set.", "Match Aliases", "Icon!")
        return
    }

    suggestions := BuildAliasSuggestions(channels)
    if (suggestions.Length = 0) {
        extra := ""
        if (SearchEdit.Value != "")
            extra := "`n`nThe search box is filtering the list. Clear it to match every loaded channel."
        MsgBox("No alias matches were found for the " channels.Length " channels currently shown." extra, "Match Aliases", "Icon!")
        return
    }

    ShowSuggestionWindow(suggestions, channels.Length)
}

ShowSuggestionWindow(suggestions, visibleCount) {
    global SuggestionGui, SuggestionLV, SuggestionRows, MainGui, SearchEdit

    CloseSuggestionWindow()
    SuggestionRows := suggestions

    checked := 0
    for suggestion in suggestions {
        if (ShouldPrecheckSuggestion(suggestion))
            checked++
    }

    SuggestionGui := Gui("+Owner" MainGui.Hwnd, "Alias Match Suggestions")
    SuggestionGui.SetFont("s9", "Segoe UI")
    SuggestionGui.OnEvent("Close", CloseSuggestionWindow)

    filterNote := (SearchEdit.Value != "") ? " Search is filtering the list." : ""
    intro := "Best match for each set, from " visibleCount " listed channels. "
        . checked " strong matches for empty sets are checked." filterNote
        . "`nAccept copies the channel name and program number into the set, the same way the arrow button does."
    SuggestionGui.AddText("x12 y10 w900 h40", intro)

    SuggestionLV := SuggestionGui.AddListView("x12 y64 w900 h360 Checked -Multi", ["Set", "Set Name", "VCh", "Channel", "Program #", "Matched Alias", "Score", "Status"])
    SuggestionLV.ModifyCol(1, 45)
    SuggestionLV.ModifyCol(2, 120)
    SuggestionLV.ModifyCol(3, 50)
    SuggestionLV.ModifyCol(4, 180)
    SuggestionLV.ModifyCol(5, 75)
    SuggestionLV.ModifyCol(6, 140)
    SuggestionLV.ModifyCol(7, 50)
    SuggestionLV.ModifyCol(8, 220)

    for suggestion in suggestions {
        options := ShouldPrecheckSuggestion(suggestion) ? "Check" : ""
        SuggestionLV.Add(options
            , suggestion.SetIndex
            , suggestion.SetName
            , suggestion.VirtualChannel
            , suggestion.ChannelName
            , suggestion.ProgramNum
            , suggestion.MatchedAlias
            , suggestion.Score "%"
            , SuggestionStatus(suggestion))
    }

    acceptBtn := SuggestionGui.AddButton("x12 y436 w150 h28", "Accept Checked")
    acceptBtn.OnEvent("Click", AcceptAliasSuggestions)

    checkAllBtn := SuggestionGui.AddButton("x170 y436 w100 h28", "Check All")
    checkAllBtn.OnEvent("Click", (*) => SetSuggestionChecks("all"))

    uncheckBtn := SuggestionGui.AddButton("x278 y436 w110 h28", "Uncheck All")
    uncheckBtn.OnEvent("Click", (*) => SetSuggestionChecks("none"))

    highBtn := SuggestionGui.AddButton("x396 y436 w180 h28", "Check High Confidence")
    highBtn.OnEvent("Click", (*) => SetSuggestionChecks("high"))

    closeBtn := SuggestionGui.AddButton("x792 y436 w120 h28", "Close")
    closeBtn.OnEvent("Click", CloseSuggestionWindow)

    SuggestionGui.Show("w924 h480")
}

SetSuggestionChecks(mode) {
    global SuggestionLV, SuggestionRows
    if (!IsObject(SuggestionLV))
        return

    Loop SuggestionRows.Length {
        check := false
        if (mode = "all")
            check := true
        else if (mode = "high" && ShouldPrecheckSuggestion(SuggestionRows[A_Index]))
            check := true

        if (check)
            SuggestionLV.Modify(A_Index, "Check")
        else
            SuggestionLV.Modify(A_Index, "-Check")
    }
}

AcceptAliasSuggestions(*) {
    global SuggestionLV, SuggestionRows
    if (!IsObject(SuggestionLV))
        return

    accepted := 0
    row := 0
    while (row := SuggestionLV.GetNext(row, "Checked")) {
        if (row < 1 || row > SuggestionRows.Length)
            continue
        suggestion := SuggestionRows[row]
        if (ApplyChannelToSet(suggestion.SetIndex, suggestion.ChannelName, suggestion.ProgramNum))
            accepted++
    }

    if (accepted = 0) {
        MsgBox("Check one or more suggestions to assign.", "Match Aliases", "Icon!")
        return
    }

    CloseSuggestionWindow()
    suffix := (accepted = 1) ? "" : "s"
    MsgBox("Assigned " accepted " channel" suffix ".", "Match Aliases", "Iconi")
}

ApplyChannelToSet(setIndex, channelName, programNum) {
    global ChannelSets
    for set in ChannelSets {
        if (set.Index = setIndex && set.HasOwnProp("NameEdit") && set.HasOwnProp("ProgramEdit")) {
            set.NameEdit.Value := channelName
            set.ProgramEdit.Value := programNum
            return true
        }
    }
    return false
}

CloseSuggestionWindow(*) {
    global SuggestionGui, SuggestionLV, SuggestionRows
    gui := SuggestionGui
    SuggestionGui := ""
    SuggestionLV := ""
    SuggestionRows := []
    if (IsObject(gui))
        gui.Destroy()
}

; ---------------------------------------------------------------------------
; Edit Config window
; ---------------------------------------------------------------------------

EditChannelConfig(*) {
    global ConfigGui, ConfigLV, ConfigDraft, ConfigCurrentRow, ConfigLoading
    global ConfigNameEdit, ConfigVchEdit, ConfigAliasEdit, ChannelSets, MainGui

    if (IsObject(ConfigGui)) {
        ConfigGui.Show()
        return
    }

    ConfigDraft := []
    ConfigCurrentRow := 0
    ConfigLoading := true

    ConfigGui := Gui("+Owner" MainGui.Hwnd, "Edit Channel Config")
    ConfigGui.SetFont("s9", "Segoe UI")
    ConfigGui.OnEvent("Close", CloseConfigWindow)

    ConfigGui.AddText("x12 y10 w880 h32", "Edit each set's name, virtual channel, and aliases. Put one alias per line. The set name is always used as an alias when matching. Save writes ChannelSets.ini and updates the main window.")

    ConfigLV := ConfigGui.AddListView("x12 y48 w540 h470 -Multi", ["Set", "Name", "Virtual Channel", "Aliases"])
    ConfigLV.OnEvent("ItemSelect", OnConfigSelect)
    ConfigLV.ModifyCol(1, 45)
    ConfigLV.ModifyCol(2, 130)
    ConfigLV.ModifyCol(3, 110)
    ConfigLV.ModifyCol(4, 230)

    ConfigGui.AddText("x568 y48 w320 h18", "Name")
    ConfigNameEdit := ConfigGui.AddEdit("x568 y68 w320 h22")
    ConfigNameEdit.OnEvent("Change", SaveConfigFields)

    ConfigGui.AddText("x568 y100 w320 h18", "Virtual Channel")
    ConfigVchEdit := ConfigGui.AddEdit("x568 y120 w120 h22")
    ConfigVchEdit.OnEvent("Change", SaveConfigFields)

    ConfigGui.AddText("x568 y152 w320 h18", "Aliases (one per line)")
    ConfigAliasEdit := ConfigGui.AddEdit("x568 y172 w320 h250 Multi VScroll")
    ConfigAliasEdit.OnEvent("Change", SaveConfigFields)

    ConfigGui.AddText("x568 y432 w320 h52", "Aliases are other names this set's channel may use, such as ESPN HD or ESPN-E. Different station numbers (ESPN and ESPN2) should be separate aliases.")

    saveBtn := ConfigGui.AddButton("x568 y492 w150 h30", "Save")
    saveBtn.OnEvent("Click", SaveChannelConfig)

    cancelBtn := ConfigGui.AddButton("x728 y492 w150 h30", "Cancel")
    cancelBtn.OnEvent("Click", CloseConfigWindow)

    ConfigLV.Opt("-Redraw")
    for set in ChannelSets {
        draft := {}
        draft.Index := set.Index
        draft.Name := set.HasOwnProp("DefaultName") ? set.DefaultName : ""
        draft.VirtualChannel := set.HasOwnProp("VirtualChannel") ? set.VirtualChannel : ""
        draft.Aliases := CloneAliasList(set.HasOwnProp("Aliases") ? set.Aliases : [])
        ConfigDraft.Push(draft)
        ConfigLV.Add("", draft.Index, draft.Name, draft.VirtualChannel, FormatAliasDisplay(draft.Aliases))
    }
    ConfigLV.Opt("+Redraw")

    if (ConfigDraft.Length > 0) {
        ConfigCurrentRow := 1
        LoadConfigFields(1)
        ConfigLV.Modify(1, "Select Focus")
    }
    ConfigLoading := false

    ConfigGui.Show("w910 h540")
}

OnConfigSelect(LV, row, selected) {
    global ConfigCurrentRow, ConfigLoading
    if (ConfigLoading || !selected)
        return
    SaveConfigFields()
    ConfigCurrentRow := row
    LoadConfigFields(row)
}

LoadConfigFields(row) {
    global ConfigDraft, ConfigLoading, ConfigNameEdit, ConfigVchEdit, ConfigAliasEdit
    if (row < 1 || row > ConfigDraft.Length)
        return

    ; Keep the caller's loading flag so the initial selection does not
    ; write the edit boxes back over the draft.
    wasLoading := ConfigLoading
    ConfigLoading := true
    draft := ConfigDraft[row]
    ConfigNameEdit.Value := draft.Name
    ConfigVchEdit.Value := draft.VirtualChannel
    ConfigAliasEdit.Value := JoinWith(draft.Aliases, "`r`n")
    ConfigLoading := wasLoading
}

SaveConfigFields(*) {
    global ConfigDraft, ConfigCurrentRow, ConfigLoading, ConfigLV
    global ConfigNameEdit, ConfigVchEdit, ConfigAliasEdit
    if (ConfigLoading || ConfigCurrentRow < 1 || ConfigCurrentRow > ConfigDraft.Length)
        return
    if (!IsObject(ConfigNameEdit))
        return

    draft := ConfigDraft[ConfigCurrentRow]
    draft.Name := CleanIniValue(ConfigNameEdit.Value)
    draft.VirtualChannel := CleanIniValue(ConfigVchEdit.Value)
    draft.Aliases := ParseAliasList(ConfigAliasEdit.Value)
    ConfigDraft[ConfigCurrentRow] := draft

    if (IsObject(ConfigLV))
        ConfigLV.Modify(ConfigCurrentRow, "", draft.Index, draft.Name, draft.VirtualChannel, FormatAliasDisplay(draft.Aliases))
}

SaveChannelConfig(*) {
    global ConfigDraft
    SaveConfigFields()

    iniPath := A_ScriptDir "\ChannelSets.ini"
    try {
        WriteChannelConfigIni(iniPath, ConfigDraft)
    } catch as e {
        MsgBox("Could not save ChannelSets.ini:`n" e.Message, "Edit Config", "Icon!")
        return
    }

    ApplyConfigToGui(ConfigDraft)
    CloseConfigWindow()
    MsgBox("Saved channel set config.`n`nNames, virtual channels, and aliases are updated.", "Edit Config", "Iconi")
}

WriteChannelConfigIni(path, drafts) {
    content := ""
    for draft in drafts {
        content .= "[Set" draft.Index "]`n"
        content .= "Name=" CleanIniValue(draft.Name) "`n"
        content .= "VirtualChannel=" CleanIniValue(draft.VirtualChannel) "`n"
        content .= "Aliases=" FormatAliasList(draft.Aliases) "`n`n"
    }

    ; Write beside the real file first so a failed save does not erase it.
    temp := path ".tmp"
    if (FileExist(temp))
        FileDelete(temp)
    FileAppend(content, temp, "UTF-8")
    FileMove(temp, path, 1)
}

ApplyConfigToGui(drafts) {
    global ChannelSets
    for draft in drafts {
        for set in ChannelSets {
            if (set.Index != draft.Index)
                continue
            set.DefaultName := draft.Name
            set.VirtualChannel := draft.VirtualChannel
            set.Aliases := CloneAliasList(draft.Aliases)
            if (set.HasOwnProp("Label"))
                set.Label.Text := DisplayLabel(draft.Name, draft.Index)
            if (set.HasOwnProp("VirtualChannelEdit"))
                set.VirtualChannelEdit.Value := draft.VirtualChannel
            break
        }
    }
}

CloseConfigWindow(*) {
    global ConfigGui, ConfigLV, ConfigDraft, ConfigCurrentRow
    global ConfigNameEdit, ConfigVchEdit, ConfigAliasEdit
    gui := ConfigGui
    ConfigGui := ""
    ConfigLV := ""
    ConfigNameEdit := ""
    ConfigVchEdit := ""
    ConfigAliasEdit := ""
    ConfigDraft := []
    ConfigCurrentRow := 0
    if (IsObject(gui))
        gui.Destroy()
}
