#Requires AutoHotkey v2.0
#SingleInstance Force

; Standalone QAM XML rewriter and uploader.
; Does not include or call any other script in this repo.
;
; Two edits, and nothing else:
;   1. Replace the first <QAM_Mapping view="Mappings">, the last
;      </QAM_Mapping>, and everything between them with the replacement text.
;   2. Replace the number inside each <Source_ID>...</Source_ID>.
; The rest of the file is copied byte for byte, then the result can be
; POSTed as multipart field "Import".

OPEN_TAG := "<QAM_Mapping view=`"Mappings`">"
CLOSE_TAG := "</QAM_Mapping>"
SOURCE_OPEN := "<Source_ID>"
SOURCE_CLOSE := "</Source_ID>"
FORM_FIELD := "Import"
DEFAULT_REPLACEMENT := "PLACEHOLDER"
DEFAULT_PART_TYPE := "text/xml"
BROWSER_UA := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

global Ui := {}
global Tests := {failures: 0}

if (A_Args.Length >= 1 && StrLower(A_Args[1]) == "/selftest")
    ExitApp(RunSelfTest())

StartGui()

; ---------------------------------------------------------------- GUI

StartGui() {
    global Ui
    saved := LoadSettings()

    g := Gui("+E0x10", "QAM XML Import")
    g.MarginX := 12
    g.MarginY := 10
    g.SetFont("s9", "Segoe UI")
    g.OnEvent("Close", CloseGui)
    g.OnEvent("DropFiles", OnDropFiles)

    g.AddText(, "XML file")
    Ui.Xml := g.AddEdit("xm y+4 w620")
    Ui.BrowseBtn := g.AddButton("x+8 yp-1 w90", "Browse")
    Ui.BrowseBtn.OnEvent("Click", BrowseXml)

    g.AddText("xm y+10", "New Source ID")
    Ui.SourceId := g.AddEdit("x+8 yp-2 w120")
    g.AddText("x+16 yp+2", "Upload filename")
    Ui.UploadName := g.AddEdit("x+8 yp-2 w250")

    g.AddText("xm y+10", "Upload URL")
    Ui.Url := g.AddEdit("xm y+4 w718")

    g.AddText("xm y+10", "Authorization")
    g.AddText("xm y+6", "Username")
    Ui.Username := g.AddEdit("x+8 yp-2 w240")
    g.AddText("x+16 yp+2", "Password")
    Ui.Password := g.AddEdit("x+8 yp-2 w240 Password")

    g.AddText("xm y+10", "Part content type")
    Ui.PartType := g.AddEdit("x+8 yp-2 w160", DEFAULT_PART_TYPE)
    Ui.SendPartType := g.AddCheckbox("x+12 yp+2 Checked", "Send part type")
    Ui.IgnoreTls := g.AddCheckbox("x+12 yp", "Ignore TLS certificate errors")

    g.AddText("xm y+10", "Text that replaces the QAM_Mapping block, including both tags")
    Ui.Replacement := g.AddEdit("xm y+4 w718 r5 Multi WantReturn")
    SendMessage(0xC5, 20000000, 0, Ui.Replacement.Hwnd)

    Ui.RewriteBtn := g.AddButton("xm y+10 w160 h28", "Rewrite XML")
    Ui.RewriteBtn.OnEvent("Click", (*) => RunJob(false))
    Ui.UploadBtn := g.AddButton("x+8 yp w200 h28", "Rewrite and Upload")
    Ui.UploadBtn.OnEvent("Click", (*) => RunJob(true))

    g.AddText("xm y+10", "Log")
    Ui.Log := g.AddEdit("xm y+4 w718 r8 ReadOnly Multi")
    SendMessage(0xC5, 5000000, 0, Ui.Log.Hwnd)

    Ui.Xml.Value := saved.XmlPath
    Ui.SourceId.Value := saved.SourceId
    Ui.UploadName.Value := saved.UploadName
    Ui.Url.Value := saved.Url
    Ui.Username.Value := saved.Username
    Ui.Password.Value := saved.Password
    Ui.PartType.Value := saved.PartType
    Ui.SendPartType.Value := saved.SendPartType
    Ui.IgnoreTls.Value := saved.IgnoreTls
    Ui.Replacement.Value := ToEditNewlines(saved.Replacement)

    g.Show("w760 h640")
}

CloseGui(*) {
    try
        SaveSettings(CollectForm())
    catch as err
        MsgBox(err.Message, "QAM XML Import", "Icon!")
    ExitApp()
}

BrowseXml(*) {
    global Ui
    start := Trim(Ui.Xml.Value)
    selected := FileSelect(1, start, "Select the XML file", "XML files (*.xml)")
    if (selected == "")
        return
    ApplySelectedFile(selected)
}

OnDropFiles(thisGui, ctrl, files, *) {
    if (files.Length < 1)
        return
    ApplySelectedFile(files[1])
}

ApplySelectedFile(path) {
    global Ui
    Ui.Xml.Value := path
    SplitPath(path, &name)
    Ui.UploadName.Value := name
}

RunJob(doUpload) {
    global Ui
    SetBusy(true)
    try {
        form := CollectForm()
        SaveSettings(form)
        form := ValidateReady(form, doUpload)

        Log("Reading " form.XmlPath)
        original := ReadRaw(form.XmlPath)
        result := RewriteXml(original, form.Replacement, form.SourceId)
        outPath := ModifiedPath(form.XmlPath)
        if (StrLower(outPath) == StrLower(form.XmlPath))
            throw Error("Refusing to overwrite the original XML file.")

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
        Log("Wrote " outPath " (" result.bytes.Size " bytes). Original file was not changed.")

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
    names := ["Xml", "SourceId", "UploadName", "Url", "Username", "Password", "PartType", "Replacement", "IgnoreTls", "SendPartType", "RewriteBtn", "UploadBtn", "BrowseBtn"]
    for name in names {
        ctrl := Ui.%name%
        if (IsObject(ctrl))
            ctrl.Enabled := !busy
    }
}

CollectForm() {
    global Ui
    partType := Trim(Ui.PartType.Value)
    sendPartType := Ui.SendPartType.Value ? true : false
    return {
        XmlPath: Trim(Ui.Xml.Value),
        SourceId: Trim(Ui.SourceId.Value),
        UploadName: Trim(Ui.UploadName.Value),
        Url: Trim(Ui.Url.Value),
        Username: CleanCredential(Ui.Username.Value, true),
        Password: CleanCredential(Ui.Password.Value, false),
        PartType: partType,
        SendPartType: sendPartType,
        IgnoreTls: Ui.IgnoreTls.Value ? true : false,
        Replacement: ToEditNewlines(Ui.Replacement.Value),
        Disposition: ""
    }
}

ValidateReady(form, doUpload) {
    if (form.XmlPath == "")
        throw Error("Choose an XML file.")
    attr := FileExist(form.XmlPath)
    if (!attr)
        throw Error("File not found: " form.XmlPath)
    if (InStr(attr, "D"))
        throw Error("Choose an XML file, not a folder.")
    if (form.PartType != "" && RegExMatch(form.PartType, "[\r\n`"]"))
        throw Error("The part content type cannot contain quotes or line breaks.")
    if (form.Replacement == "")
        throw Error("The mapping replacement text is empty. Use PLACEHOLDER until the real text is ready.")

    form.UploadName := SanitizeFilename(form.UploadName)
    form.Disposition := Format("Content-Disposition: form-data; name=`"{1}`"; filename=`"{2}`"", FORM_FIELD, form.UploadName)
    ValidateSourceId(form.SourceId)
    if (doUpload) {
        ValidateUpload(form)
        if (!form.SendPartType)
            form.PartType := ""
    }
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

ModifiedPath(xmlPath) {
    SplitPath(xmlPath, , &dir, &ext, &nameNoExt)
    if (dir == "")
        dir := A_ScriptDir
    dir := RTrim(dir, "\/")
    if (ext == "")
        return dir "\" nameNoExt ".modified"
    return dir "\" nameNoExt ".modified." ext
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

; ---------------------------------------------------------------- upload

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
        throw Error("Upload failed. " err.Message)

    status := 0
    statusText := ""
    bodyText := ""
    finalUrl := ""
    try {
        status := whr.Status
        statusText := whr.StatusText
    } catch as err {
        throw Error("Upload failed. " err.Message)
    }
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

ReplacementPath() {
    return A_ScriptDir "\MappingReplacement.txt"
}

LoadSettings() {
    replacement := DEFAULT_REPLACEMENT
    if (FileExist(ReplacementPath()))
        replacement := FileRead(ReplacementPath(), "UTF-8")
    return {
        XmlPath: ReadIni("XmlPath", ""),
        SourceId: ReadIni("SourceId", ""),
        UploadName: ReadIni("UploadName", ""),
        Url: ReadIni("Url", ""),
        Username: ReadIni("Username", ""),
        Password: ReadIni("Password", ""),
        PartType: ReadIni("PartType", DEFAULT_PART_TYPE),
        SendPartType: ReadIni("SendPartType", "1") != "0",
        IgnoreTls: ReadIni("IgnoreTls", "1") != "0",
        Replacement: replacement
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
    WriteIni("XmlPath", form.XmlPath)
    WriteIni("SourceId", form.SourceId)
    WriteIni("UploadName", form.UploadName)
    WriteIni("Url", form.Url)
    WriteIni("Username", form.Username)
    WriteIni("Password", form.Password)
    WriteIni("PartType", form.PartType == "" ? DEFAULT_PART_TYPE : form.PartType)
    WriteIni("SendPartType", form.SendPartType ? "1" : "0")
    WriteIni("IgnoreTls", form.IgnoreTls ? "1" : "0")
    WriteTextIfChanged(ReplacementPath(), form.Replacement)
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

WriteTextIfChanged(path, text) {
    existing := ""
    if (FileExist(path))
        existing := FileRead(path, "UTF-8")
    if (NormalizeNewlines(existing) == NormalizeNewlines(text))
        return
    f := FileOpen(path, "w", "UTF-8-RAW")
    f.Write(text)
    f.Close()
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
