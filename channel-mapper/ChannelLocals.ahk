; ChannelLocals.ahk - Match local call signs to the main list and to sets.
; Included by ChannelMapper.ahk and ChannelMapper_Standalone.ahk.
;
; Get Locals reads an array of "CALLSIGN - NETWORK" strings, finds that
; station in the Name column of the main list, then matches the network
; to a set name or alias the same way Match Aliases does.
; Names that contain "Spectrum News" keep the call sign and always pair
; with the set named Spectrum News or the alias Spectrum News 1.

; Call signs should be a near-exact match to the list-view name.
global LocalCallsignMatchThreshold := 94

; ---------------------------------------------------------------------------
; Locals source
; ---------------------------------------------------------------------------

; Placeholder until the real locals source is wired in.
; Replace the body of this function with the implemented call-sign method.
; Only entries that contain a dash with spaces, such as " - ", are used,
; except Spectrum News names, which ignore the text after the dash.
GetLocalCallSigns() {
    return [
        "WTMU - Telemundo",
        "KTIV - CBS",
        "KCAU - ABC",
        "KMEG - FOX",
        "KPTH - MyNetwork"
    ]
}

; ---------------------------------------------------------------------------
; Parsing and matching
; ---------------------------------------------------------------------------

ContainsSpectrumNews(str) {
    return InStr(str, "Spectrum News", false)
}

; Split "KTIV - CBS" into call sign and network. Uses the first dash that
; has a space after it so "WTMU-LD - Telemundo" keeps WTMU-LD together.
; Spectrum News keeps the call sign and ignores the text after " - ".
ParseLocalEntry(str) {
    str := Trim(str)
    if (str = "")
        return false

    spectrum := ContainsSpectrumNews(str)

    ; Allow regular, en, or em dashes, and extra spaces around them.
    if RegExMatch(str, "i)^(.+?)\s+[-–—]\s+(.+)$", &match) {
        left := Trim(match[1])
        right := Trim(match[2])
        entry := {}
        ; "WXXX - Spectrum News 1" keeps WXXX. "Spectrum News - Buffalo"
        ; has no call sign, so search the list for Spectrum News.
        if (spectrum && ContainsSpectrumNews(left))
            entry.Callsign := "Spectrum News"
        else
            entry.Callsign := left
        entry.Network := spectrum ? "Spectrum News" : right
        entry.Raw := str
        entry.SpectrumNews := spectrum
        if (entry.Callsign = "" || entry.Network = "")
            return false
        return entry
    }

    if (spectrum) {
        entry := {}
        entry.Callsign := str
        entry.Network := "Spectrum News"
        entry.Raw := str
        entry.SpectrumNews := true
        return entry
    }

    return false
}

; Text before the first " - ", or the first word if there is no dash.
; "WTMU - Telemundo" and "WTMU-LD" both yield a call-sign token.
FirstNameSegment(str) {
    str := Trim(str)
    if (str = "")
        return ""
    if RegExMatch(str, "i)^(.+?)\s+[-–—]\s+", &match)
        return Trim(match[1])
    tokens := StrSplit(NormalizeChannelName(str), " ")
    if (tokens.Length = 0)
        return ""
    return tokens[1]
}

CallsignQualitySuffixes() {
    return ["hevc", "dtv", "fhd", "uhd", "hdr", "hd", "sd", "tv"]
}

; True when the list name is the call sign plus a glued quality word.
; "WTMUHD" matches "WTMU". Do not use SplitGluedQualitySuffix here: that
; peels "uhd" first and turns WTMUHD into WTM, which then fails to match.
ChannelIsCallsignPlusSuffix(channelName, callsign) {
    chan := NormalizeChannelName(channelName)
    call := NormalizeChannelName(callsign)
    if (chan = "" || call = "")
        return false
    if (chan = call)
        return true
    for suffix in CallsignQualitySuffixes() {
        sufLen := StrLen(suffix)
        if (StrLen(chan) > sufLen && SubStr(chan, -sufLen) = suffix) {
            stem := SubStr(chan, 1, StrLen(chan) - sufLen)
            if (stem = call)
                return true
        }
    }
    return false
}

; Compare a listed channel name to a local call sign.
; Prefer the first segment so "WTMU - Telemundo" matches "WTMU".
; Also accept glued suffixes so "WTMUHD" matches "WTMU".
ScoreCallsignMatch(channelName, callsign) {
    callNorm := NormalizeChannelName(callsign)
    chanNorm := NormalizeChannelName(channelName)
    if (callNorm = "" || chanNorm = "")
        return 0
    if (chanNorm = callNorm)
        return 100
    if (ChannelIsCallsignPlusSuffix(channelName, callsign))
        return 100

    firstNorm := NormalizeChannelName(FirstNameSegment(channelName))
    if (firstNorm != "" && firstNorm = callNorm)
        return 100
    if (firstNorm != "" && ChannelIsCallsignPlusSuffix(firstNorm, callsign))
        return 100

    callFirst := NormalizeChannelName(FirstNameSegment(callsign))
    if (firstNorm != "" && callFirst != "" && firstNorm = callFirst)
        return 100

    return ScoreAliasMatch(channelName, callsign)
}

; Use every loaded channel, not just the current search filter.
GetChannelsForLocalMatch() {
    global FullChannelList
    if (IsObject(FullChannelList) && FullChannelList.Length > 0)
        return FullChannelList
    return GetVisibleChannels()
}

ScoreSpectrumNewsChannel(channelName) {
    if (ContainsSpectrumNews(channelName))
        return 100
    compact := StrReplace(NormalizeChannelName(channelName), " ", "")
    if (compact != "" && InStr(compact, "spectrumnews"))
        return 96
    return 0
}

; Find the list-view row for a local. Try the call sign first, then the
; full "CALL - NETWORK" string, then the network name (Telemundo).
; Spectrum News also matches any list name that contains Spectrum News,
; so "Spectrum News - Buffalo" still pairs when there is no call sign.
FindChannelForLocal(channels, parsed) {
    global LocalCallsignMatchThreshold, AliasMatchShowThreshold, AliasMatchCheckThreshold

    bestScore := -1
    bestChannel := ""
    for channel in channels {
        callScore := ScoreCallsignMatch(channel.Name, parsed.Callsign)
        rawScore := 0
        if (NormalizeChannelName(channel.Name) = NormalizeChannelName(parsed.Raw))
            rawScore := 100
        else
            rawScore := ScoreAliasMatch(channel.Name, parsed.Raw)
        netScore := ScoreAliasMatch(channel.Name, parsed.Network)
        specScore := 0
        if (parsed.HasOwnProp("SpectrumNews") && parsed.SpectrumNews)
            specScore := ScoreSpectrumNewsChannel(channel.Name)

        score := 0
        if (specScore >= LocalCallsignMatchThreshold)
            score := specScore
        else if (callScore >= LocalCallsignMatchThreshold)
            score := callScore
        else if (rawScore >= AliasMatchShowThreshold)
            score := rawScore
        else if (netScore >= AliasMatchCheckThreshold)
            score := netScore
        if (score = 0)
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

IsSpectrumNewsSetAlias(name) {
    norm := NormalizeChannelName(name)
    if (norm = "")
        return 0
    if (norm = "spectrum news")
        return 100
    if (norm = "spectrum news 1")
        return 99
    if (InStr(norm, "spectrum news") = 1)
        return 90
    return 0
}

; Set named "Spectrum News", or a set whose aliases include "Spectrum News 1".
FindSpectrumNewsSet() {
    global ChannelSets

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
            score := IsSpectrumNewsSetAlias(alias)
            if (score = 0)
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

; Best set whose name or aliases match the network (CBS, Telemundo, ...).
FindSetByNetwork(network) {
    global ChannelSets, AliasMatchShowThreshold

    netNorm := NormalizeChannelName(network)
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
            score := 0
            if (netNorm != "" && NormalizeChannelName(alias) = netNorm)
                score := 100
            else
                score := Max(ScoreAliasMatch(alias, network), ScoreAliasMatch(network, alias))
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

; One suggestion per set. Each local must match a list-view channel and a set.
BuildLocalSuggestions(channels, locals) {
    result := {}
    result.Suggestions := []
    result.Skipped := []
    bySet := Map()

    for localx in locals {
        parsed := ParseLocalEntry(localx)
        if (!IsObject(parsed))
            continue

        channelMatch := FindChannelForLocal(channels, parsed)
        if (!IsObject(channelMatch)) {
            result.Skipped.Push(parsed.Raw ": no list channel matching " parsed.Callsign)
            continue
        }

        if (parsed.HasOwnProp("SpectrumNews") && parsed.SpectrumNews)
            setMatch := FindSpectrumNewsSet()
        else
            setMatch := FindSetByNetwork(parsed.Network)
        if (!IsObject(setMatch)) {
            if (parsed.HasOwnProp("SpectrumNews") && parsed.SpectrumNews)
                result.Skipped.Push(parsed.Raw ": no set named Spectrum News (or alias Spectrum News 1)")
            else
                result.Skipped.Push(parsed.Raw ": no set named " parsed.Network)
            continue
        }

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
            if (!keepNew) {
                result.Skipped.Push(parsed.Raw ": set " suggestion.SetName " already has a stronger local match")
                continue
            }
        }
        bySet[set.Index] := suggestion
    }

    for index, suggestion in bySet
        result.Suggestions.Push(suggestion)

    MarkSharedSuggestions(result.Suggestions)
    SortSuggestions(result.Suggestions)
    return result
}

CountUsableLocals(locals) {
    count := 0
    for localx in locals {
        if (IsObject(ParseLocalEntry(localx)))
            count++
    }
    return count
}

FormatSkipReasons(skipped) {
    if (skipped.Length = 0)
        return ""
    text := ""
    limit := Min(skipped.Length, 8)
    Loop limit
        text .= "`n- " skipped[A_Index]
    if (skipped.Length > limit)
        text .= "`n- ... and " (skipped.Length - limit) " more"
    return text
}

; ---------------------------------------------------------------------------
; Button handler
; ---------------------------------------------------------------------------

SuggestLocalMatches(*) {
    global ChannelSets, SearchEdit

    channels := GetChannelsForLocalMatch()
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

    built := BuildLocalSuggestions(channels, locals)
    suggestions := built.Suggestions
    if (suggestions.Length = 0) {
        extra := FormatSkipReasons(built.Skipped)
        if (SearchEdit.Value != "")
            extra .= "`n`nThe search box is filtering the list. Get Locals still uses every loaded channel."
        MsgBox("No local matches were found.`n`nLooked at " usable " local entries and " channels.Length " loaded channels." extra, "Get Locals", "Icon!")
        return
    }

    intro := "Matched local call signs to loaded channel names, then matched the network to each set's name and aliases. "
        . "From " usable " local entries and " channels.Length " loaded channels."
    if (built.Skipped.Length > 0)
        intro .= " " built.Skipped.Length " local" (built.Skipped.Length = 1 ? "" : "s") " did not match."
    ShowSuggestionWindow(suggestions, channels.Length, "Local Channel Suggestions", "Get Locals", intro)
}
