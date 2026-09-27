; ChannelLocals.ahk - Match local call signs to the main list and to sets.
; Included by ChannelMapper.ahk and ChannelMapper_Standalone.ahk.
;
; Get Locals reads an array of "CALLSIGN - NETWORK" strings, finds the
; call sign in the Name column of the main list (LV column 3), then matches
; the network to a set name or alias the same way Match Aliases does.

; Call signs should be a near-exact match to the list-view name.
global LocalCallsignMatchThreshold := 94

; ---------------------------------------------------------------------------
; Locals source
; ---------------------------------------------------------------------------

; Placeholder until the real locals source is wired in.
; Replace the body of this function with the implemented call-sign method.
; Only entries that contain " - " are used.
GetLocalCallSigns() {
    return [
        "KTIV - CBS",
        "KCAU - ABC",
        "KMEG - FOX",
        "KPTH - MyNetwork"
    ]
}

; ---------------------------------------------------------------------------
; Parsing and matching
; ---------------------------------------------------------------------------

; Split "KTIV - CBS" into call sign and network. Uses the first " - " only
; so extra text after the network is kept with the network name.
ParseLocalEntry(str) {
    str := Trim(str)
    sep := " - "
    pos := InStr(str, sep)
    if (pos = 0)
        return false

    entry := {}
    entry.Callsign := Trim(SubStr(str, 1, pos - 1))
    entry.Network := Trim(SubStr(str, pos + StrLen(sep)))
    entry.Raw := str
    if (entry.Callsign = "" || entry.Network = "")
        return false
    return entry
}

; Best list-view channel whose Name (column 3) matches the call sign.
FindChannelByCallsign(channels, callsign) {
    global LocalCallsignMatchThreshold

    bestScore := -1
    bestChannel := ""
    for channel in channels {
        score := ScoreCallsignMatch(channel.Name, callsign)
        if (score < LocalCallsignMatchThreshold)
            continue
        better := false
        if (score > bestScore)
            better := true
        else if (score = bestScore && IsObject(bestChannel) && SafeProgramNum(channel.ProgramNum) < SafeProgramNum(bestChannel.ProgramNum))
            better := true
        if (better) {
            bestScore := score
            bestChannel := channel
        }
    }

    if (!IsObject(bestChannel))
        return false

    result := {}
    result.Channel := bestChannel
    result.Score := bestScore
    return result
}

; Exact normalized names count as 100. Otherwise reuse alias scoring so
; "KTIV HD" still matches the call sign "KTIV".
ScoreCallsignMatch(channelName, callsign) {
    if (NormalizeChannelName(channelName) = NormalizeChannelName(callsign) && NormalizeChannelName(callsign) != "")
        return 100
    return ScoreAliasMatch(channelName, callsign)
}

; Best set whose name or aliases match the network (CBS, ABC, ...).
FindSetByNetwork(network) {
    global ChannelSets, AliasMatchShowThreshold

    bestScore := -1
    bestSet := ""
    bestAlias := ""
    for set in ChannelSets {
        aliases := CollectSetAliases(set)
        if (aliases.Length = 0)
            continue
        if (!set.HasOwnProp("NameEdit") || !set.HasOwnProp("ProgramEdit"))
            continue

        for alias in aliases {
            score := ScoreAliasMatch(network, alias)
            if (score < AliasMatchShowThreshold)
                continue
            better := false
            if (score > bestScore)
                better := true
            else if (score = bestScore && IsObject(bestSet) && set.Index < bestSet.Index)
                better := true
            if (better) {
                bestScore := score
                bestSet := set
                bestAlias := alias
            }
        }
    }

    if (!IsObject(bestSet))
        return false

    result := {}
    result.Set := bestSet
    result.MatchedAlias := bestAlias
    result.Score := bestScore
    return result
}

; One suggestion per set. Each local must match a list-view call sign and a set.
BuildLocalSuggestions(channels, locals) {
    suggestions := []
    bySet := Map()

    for local in locals {
        parsed := ParseLocalEntry(local)
        if (!IsObject(parsed))
            continue

        channelMatch := FindChannelByCallsign(channels, parsed.Callsign)
        if (!IsObject(channelMatch))
            continue

        setMatch := FindSetByNetwork(parsed.Network)
        if (!IsObject(setMatch))
            continue

        set := setMatch.Set
        channel := channelMatch.Channel
        ; Prefer the weaker of the two steps so a shaky network match
        ; is not hidden behind a perfect call-sign match.
        score := Min(channelMatch.Score, setMatch.Score)

        suggestion := {}
        suggestion.SetIndex := set.Index
        suggestion.SetName := (set.DefaultName != "") ? set.DefaultName : "Set " set.Index
        suggestion.VirtualChannel := set.VirtualChannel
        suggestion.ChannelName := channel.Name
        suggestion.ProgramNum := channel.ProgramNum
        suggestion.MatchedAlias := parsed.Raw
        suggestion.Score := score
        suggestion.CurrentName := set.NameEdit.Value
        suggestion.CurrentProgram := set.ProgramEdit.Value
        suggestion.Shared := 0

        if (bySet.Has(set.Index)) {
            existing := bySet[set.Index]
            keepNew := false
            if (suggestion.Score > existing.Score)
                keepNew := true
            else if (suggestion.Score = existing.Score && SafeProgramNum(suggestion.ProgramNum) < SafeProgramNum(existing.ProgramNum))
                keepNew := true
            if (!keepNew)
                continue
        }
        bySet[set.Index] := suggestion
    }

    for index, suggestion in bySet
        suggestions.Push(suggestion)

    MarkSharedSuggestions(suggestions)
    SortSuggestions(suggestions)
    return suggestions
}

CountUsableLocals(locals) {
    count := 0
    for local in locals {
        if (IsObject(ParseLocalEntry(local)))
            count++
    }
    return count
}

; ---------------------------------------------------------------------------
; Button handler
; ---------------------------------------------------------------------------

SuggestLocalMatches(*) {
    global ChannelSets, SearchEdit

    channels := GetVisibleChannels()
    if (channels.Length = 0) {
        MsgBox("Load channels before matching locals.`n`nThe channel list is empty.", "Get Locals", "Icon!")
        return
    }

    locals := GetLocalCallSigns()
    usable := CountUsableLocals(locals)
    if (usable = 0) {
        MsgBox("No local call signs are available.`n`nGetLocalCallSigns() returned no entries in the form CALLSIGN - NETWORK.", "Get Locals", "Icon!")
        return
    }

    configured := 0
    for set in ChannelSets {
        if (CollectSetAliases(set).Length > 0)
            configured++
    }
    if (configured = 0) {
        MsgBox("No set names or aliases are configured yet.`n`nUse Edit Config to set a name and aliases for each channel set.", "Get Locals", "Icon!")
        return
    }

    suggestions := BuildLocalSuggestions(channels, locals)
    if (suggestions.Length = 0) {
        extra := ""
        if (SearchEdit.Value != "")
            extra := "`n`nThe search box is filtering the list. Clear it to match every loaded channel."
        MsgBox("No local matches were found.`n`nLooked at " usable " local entries and " channels.Length " listed channels." extra, "Get Locals", "Icon!")
        return
    }

    intro := "Matched local call signs to listed channel names, then matched the network to each set's name and aliases. "
        . "From " usable " local entries and " channels.Length " listed channels."
    ShowSuggestionWindow(suggestions, channels.Length, "Local Channel Suggestions", "Get Locals", intro)
}
