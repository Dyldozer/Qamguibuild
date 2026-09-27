#Requires AutoHotkey v2.0
#SingleInstance Force

; JSON Tree
; Paste a JSON string, or open a file, and browse the hierarchy.
; Large objects and arrays load one page at a time.

class JsonTreeApp {
    __New() {
        this.pageSize := 400
        this.matchLimit := 3000
        this.nodes := Map()
        this.loadMore := Map()
        this.matches := []
        this.matchIndex := 0
        this.lastQuery := ""
        this.matchCapped := false
        this.pathBuf := []
        this.rootId := 0
        this.external := ""
        this.suppress := false
        this.suspendSelect := false
        this.redrawDepth := 0

        this.gui := Gui("+Resize +MinSize1100x640", "JSON Tree")
        this.gui.SetFont("s9", "Segoe UI")
        this.gui.OnEvent("Close", (*) => ExitApp())
        this.gui.OnEvent("Size", this.OnSize.Bind(this))
        this.gui.OnEvent("DropFiles", this.OnDrop.Bind(this))
        this.gui.Opt("+E0x10")

        this.parseBtn := this.gui.AddButton("w84 h28", "&Parse")
        this.parseBtn.OnEvent("Click", this.Parse.Bind(this))
        this.openBtn := this.gui.AddButton("w84 h28", "&Open")
        this.openBtn.OnEvent("Click", this.OpenFile.Bind(this))
        this.clearBtn := this.gui.AddButton("w72 h28", "Clea&r")
        this.clearBtn.OnEvent("Click", this.Clear.Bind(this))
        this.collapseBtn := this.gui.AddButton("w110 h28", "&Collapse")
        this.collapseBtn.OnEvent("Click", this.CollapseAll.Bind(this))
        this.copyPathBtn := this.gui.AddButton("w100 h28", "Copy pat&h")
        this.copyPathBtn.OnEvent("Click", this.CopyPath.Bind(this))
        this.copyValueBtn := this.gui.AddButton("w108 h28", "Copy &value")
        this.copyValueBtn.OnEvent("Click", this.CopyValue.Bind(this))

        this.findLabel := this.gui.AddText("w36 h20", "Find")
        this.findPrevBtn := this.gui.AddButton("w88 h28", "&Previous")
        this.findPrevBtn.OnEvent("Click", this.FindPrev.Bind(this))
        this.findNextBtn := this.gui.AddButton("w72 h28", "&Next")
        this.findNextBtn.OnEvent("Click", this.FindNext.Bind(this))

        this.gui.SetFont("s9", "Consolas")
        this.searchEdit := this.gui.AddEdit("h24")
        this.searchEdit.OnEvent("Change", this.OnSearchChange.Bind(this))
        this.jsonEdit := this.gui.AddEdit("WantReturn VScroll")
        this.jsonEdit.OnEvent("Change", this.OnEditChange.Bind(this))

        this.gui.SetFont("s9", "Segoe UI")
        this.tv := this.gui.AddTreeView("h400")
        this.tv.OnEvent("ItemExpand", this.OnExpand.Bind(this))
        this.tv.OnEvent("ItemSelect", this.OnSelect.Bind(this))
        this.tv.OnEvent("ContextMenu", this.OnContext.Bind(this))

        this.pathLabel := this.gui.AddText("h18", "Path")
        this.typeLabel := this.gui.AddText("h18", "Type")
        this.typeText := this.gui.AddText("h20", "")
        this.valueLabel := this.gui.AddText("h18", "Value")

        this.gui.SetFont("s9", "Consolas")
        this.pathEdit := this.gui.AddEdit("r1 ReadOnly")
        this.valueEdit := this.gui.AddEdit("ReadOnly WantReturn VScroll")

        this.gui.SetFont("s9", "Segoe UI")
        this.sb := this.gui.AddStatusBar(, "Ctrl+Enter parses. Ctrl+O opens a file. Ctrl+F searches. Expand a node to load its children.")

        this.ctx := Menu()
        this.ctx.Add("Copy path", this.CopyPath.Bind(this))
        this.ctx.Add("Copy value", this.CopyValue.Bind(this))

        ; Keep these alive. The edit control may retain the pointer from EM_SETCUEBANNER.
        static cue := "Paste a JSON string here"
        static searchCue := "Key or value"
        SendMessage(0x1501, 1, StrPtr(cue), this.jsonEdit)
        SendMessage(0x1501, 1, StrPtr(searchCue), this.searchEdit)
    }

    Show() {
        this.gui.Show("w1200 h800")
        this.gui.GetClientPos(, , &w, &h)
        this.Layout(w, h)
        this.jsonEdit.Focus()
    }

    OnSize(gui, minMax, width, height) {
        if (minMax = -1)
            return
        this.Layout(width, height)
    }

    Layout(w, h) {
        if (w < 200 || h < 200)
            return
        pad := 10
        gap := 6
        btnH := 28
        measured := 0
        this.sb.GetPos(, , , &measured)
        sbH := (measured >= 16 && measured <= 80) ? measured : 22

        y := pad
        x := pad
        this.parseBtn.Move(x, y, 84, btnH)
        x += 84 + gap
        this.openBtn.Move(x, y, 84, btnH)
        x += 84 + gap
        this.clearBtn.Move(x, y, 72, btnH)
        x += 72 + gap
        this.collapseBtn.Move(x, y, 110, btnH)
        x += 110 + gap
        this.copyPathBtn.Move(x, y, 100, btnH)
        x += 100 + gap
        this.copyValueBtn.Move(x, y, 108, btnH)
        x += 108 + gap
        leftEnd := x

        right := w - pad
        this.findNextBtn.Move(right - 72, y, 72, btnH)
        right -= 72 + gap
        this.findPrevBtn.Move(right - 88, y, 88, btnH)
        right -= 88 + gap
        searchW := right - leftEnd - 40
        if (searchW < 80)
            searchW := 80
        this.findLabel.Move(leftEnd, y + 4, 36, 20)
        this.searchEdit.Move(leftEnd + 40, y + 2, searchW, 24)

        editY := y + btnH + gap
        editH := Min(200, Max(90, Round(h * 0.2)))
        this.jsonEdit.Move(pad, editY, w - pad * 2, editH)

        treeY := editY + editH + gap
        treeH := h - treeY - sbH - pad
        if (treeH < 80)
            treeH := 80
        detailW := w >= 1100 ? 380 : 320
        treeW := w - pad * 3 - detailW
        if (treeW < 240) {
            treeW := Round(w * 0.55)
            detailW := w - pad * 3 - treeW
        }
        this.tv.Move(pad, treeY, treeW, treeH)

        dx := pad + treeW + pad
        dy := treeY
        this.pathLabel.Move(dx, dy, detailW, 18)
        dy += 18
        this.pathEdit.Move(dx, dy, detailW, 22)
        dy += 28
        this.typeLabel.Move(dx, dy, detailW, 18)
        dy += 18
        this.typeText.Move(dx, dy, detailW, 36)
        dy += 40
        this.valueLabel.Move(dx, dy, detailW, 18)
        dy += 18
        valueH := treeY + treeH - dy
        if (valueH < 40)
            valueH := 40
        this.valueEdit.Move(dx, dy, detailW, valueH)
    }

    OnDrop(guiObj, ctrl, files, *) {
        if (IsObject(files) && files.Length)
            this.OpenPath(files[1])
    }

    OnEditChange(*) {
        if (this.suppress)
            return
        ; A read-only box is the large-file notice, not the JSON itself.
        style := DllCall("GetWindowLongPtr", "ptr", this.jsonEdit.Hwnd, "int", -16, "ptr")
        if (style & 0x800)
            return
        this.external := ""
    }

    OnSearchChange(*) {
        this.lastQuery := ""
        this.matchIndex := 0
    }

    OpenFile(*) {
        path := FileSelect(1, A_ScriptDir, "Open JSON file", "JSON and text (*.json; *.txt; *.log)")
        if (path = "")
            return
        this.OpenPath(path)
    }

    OpenPath(path) {
        attr := FileExist(path)
        if (attr = "") {
            this.SetStatus("File not found.")
            return
        }
        if (InStr(attr, "D")) {
            this.SetStatus("That is a folder. Open a JSON file.")
            return
        }
        this.SetStatus("Reading file...")
        Sleep(15)
        try {
            text := ReadJsonFile(path)
        } catch as err {
            this.SetStatus("Could not read the file: " err.Message)
            return
        }
        SplitPath(path, &name)
        this.LoadText(text, name)
    }

    LoadText(text, source := "") {
        this.suppress := true
        if (StrLen(text) > 200000) {
            this.external := text
            this.jsonEdit.Opt("+ReadOnly")
            label := source != "" ? source : "pasted text"
            this.jsonEdit.Value := "(This JSON is " FormatCount(StrLen(text)) " characters, so it is kept out of this box.)`r`nSource: " label "`r`n`r`nPress Clear to paste something else."
        } else {
            this.external := ""
            this.jsonEdit.Opt("-ReadOnly")
            this.jsonEdit.Value := text
        }
        this.suppress := false
        this.gui.Title := source != "" ? ("JSON Tree - " source) : "JSON Tree"
        this.Parse()
    }

    Parse(*) {
        text := this.external != "" ? this.external : this.jsonEdit.Value
        if (Trim(text) = "") {
            this.SetStatus("Paste JSON or open a file first.")
            return
        }
        this.SetStatus("Parsing...")
        Sleep(15)
        started := A_TickCount
        try {
            value := Json.Parse(text)
        } catch as err {
            this.pathEdit.Value := ""
            this.typeText.Text := "Parse error"
            this.valueEdit.Value := err.Message
            this.SetStatus("Invalid JSON. The message is in the value box.")
            return
        }
        elapsed := A_TickCount - started
        this.BuildTree(value)
        this.SetStatus("Parsed " FormatCount(StrLen(text)) " characters in " elapsed " ms. Root is " DescribeValue(value) ". Expand a node to load its children.")
        this.tv.Focus()
    }

    Clear(*) {
        this.suppress := true
        this.external := ""
        this.jsonEdit.Opt("-ReadOnly")
        this.jsonEdit.Value := ""
        this.suppress := false
        this.tv.Delete()
        this.nodes := Map()
        this.loadMore := Map()
        this.rootId := 0
        this.matches := []
        this.matchIndex := 0
        this.lastQuery := ""
        this.pathEdit.Value := ""
        this.typeText.Text := ""
        this.valueEdit.Value := ""
        this.gui.Title := "JSON Tree"
        this.SetStatus("Cleared. Paste JSON and press Ctrl+Enter, or open a file.")
        this.jsonEdit.Focus()
    }

    BuildTree(value) {
        this.BeginUpdate()
        prev := this.suspendSelect
        this.suspendSelect := true
        try {
            this.tv.Delete()
            this.nodes := Map()
            this.loadMore := Map()
            this.matches := []
            this.matchIndex := 0
            this.lastQuery := ""
            this.rootId := this.AddNode(0, "", false, value, "$")
            if (this.nodes[this.rootId].total > 0)
                this.tv.Modify(this.rootId, "Expand")
        } finally {
            this.suspendSelect := prev
            this.EndUpdate()
        }
        this.tv.Modify(this.rootId, "Select Vis")
        this.ShowDetails(this.rootId)
    }

    AddNode(parentId, key, isIndex, value, path) {
        label := this.MakeLabel(key, isIndex, value)
        id := parentId ? this.tv.Add(label, parentId) : this.tv.Add(label)
        node := TreeNode(value, path, key, isIndex)
        this.nodes[id] := node
        if (node.total > 0)
            node.placeholder := this.tv.Add("...", id)
        return id
    }

    OnExpand(ctrl, item, expanded) {
        if (!expanded || !this.nodes.Has(item))
            return
        node := this.nodes[item]
        if (node.total > 0 && node.childIds.Count = 0 && node.rangeEnd = 0)
            this.ShowRange(item, 0, this.pageSize)
    }

    OnSelect(ctrl, item) {
        if (this.suspendSelect || !item)
            return
        if (this.loadMore.Has(item)) {
            info := this.loadMore[item]
            parent := info.parent
            if (!this.nodes.Has(parent))
                return
            node := this.nodes[parent]
            if (info.dir = "next")
                this.AppendPage(parent)
            else {
                start := node.rangeStart - this.pageSize
                if (start < 0)
                    start := 0
                this.ShowRange(parent, start, this.pageSize)
            }
            return
        }
        if (this.nodes.Has(item))
            this.ShowDetails(item)
    }

    OnContext(ctrl, item, *) {
        if (!item || !this.nodes.Has(item))
            return
        this.tv.Modify(item, "Select")
        this.ctx.Show()
    }

    ShowRange(id, start, count) {
        node := this.nodes[id]
        if (node.total = 0)
            return
        if (start > node.total - 1)
            start := node.total - 1
        if (start < 0)
            start := 0
        count := Min(count, node.total - start)
        if (count < 1)
            count := 1

        this.BeginUpdate()
        prev := this.suspendSelect
        this.suspendSelect := true
        try {
            old := this.TakeOldChildren(id)
            node.rangeStart := start
            node.rangeEnd := start
            this.AddPager(id, "earlier")
            this.AddRange(id, start, count)
            node.rangeEnd := start + count
            this.AddPager(id, "next")
            for oldId in old
                this.tv.Delete(oldId)
        } finally {
            this.suspendSelect := prev
            this.EndUpdate()
        }
        last := start + count - 1
        this.SetStatus("Showing entries " FormatCount(start) " through " FormatCount(last) " of " FormatCount(node.total) ".")
    }

    AppendPage(id) {
        node := this.nodes[id]
        if (node.rangeEnd >= node.total)
            return
        if (node.childIds.Count = 0) {
            this.ShowRange(id, 0, this.pageSize)
            return
        }
        this.BeginUpdate()
        prev := this.suspendSelect
        this.suspendSelect := true
        oldMore := node.moreId
        try {
            if (oldMore && this.loadMore.Has(oldMore))
                this.loadMore.Delete(oldMore)
            node.moreId := 0
            start := node.rangeEnd
            count := Min(this.pageSize, node.total - start)
            this.AddRange(id, start, count)
            node.rangeEnd := start + count
            this.AddPager(id, "next")
            if (oldMore)
                this.tv.Delete(oldMore)
        } finally {
            this.suspendSelect := prev
            this.EndUpdate()
        }
        last := node.rangeEnd - 1
        this.SetStatus("Showing entries " FormatCount(node.rangeStart) " through " FormatCount(last) " of " FormatCount(node.total) ".")
    }

    TakeOldChildren(id) {
        node := this.nodes[id]
        old := []
        child := this.tv.GetChild(id)
        while child {
            old.Push(child)
            child := this.tv.GetNext(child)
        }
        for _, cid in node.childIds
            this.Forget(cid)
        node.childIds := Map()
        this.DropPager(node)
        return old
    }

    DropPager(node) {
        if (node.earlierId && this.loadMore.Has(node.earlierId))
            this.loadMore.Delete(node.earlierId)
        node.earlierId := 0
        if (node.moreId && this.loadMore.Has(node.moreId))
            this.loadMore.Delete(node.moreId)
        node.moreId := 0
        node.placeholder := 0
    }

    Forget(id) {
        if (this.loadMore.Has(id)) {
            this.loadMore.Delete(id)
            return
        }
        if (!this.nodes.Has(id))
            return
        node := this.nodes[id]
        for _, cid in node.childIds
            this.Forget(cid)
        this.DropPager(node)
        this.nodes.Delete(id)
    }

    AddRange(parentId, start, count) {
        parent := this.nodes[parentId]
        i := 0
        while (i < count) {
            idx := start + i
            key := this.KeyAt(parent, idx)
            val := this.ValueAt(parent, idx)
            isIndex := parent.value is Array
            path := isIndex ? (parent.path "[" key "]") : JoinKey(parent.path, key)
            childId := this.AddNode(parentId, key, isIndex, val, path)
            parent.childIds[key] := childId
            i++
        }
    }

    AddPager(parentId, dir) {
        node := this.nodes[parentId]
        if (dir = "earlier") {
            if (node.rangeStart <= 0)
                return
            label := "Earlier...  " FormatCount(node.rangeStart) " above"
            id := this.tv.Add(label, parentId, "Bold First")
            node.earlierId := id
            this.loadMore[id] := Pager(parentId, "earlier")
            return
        }
        remaining := node.total - node.rangeEnd
        if (remaining <= 0)
            return
        label := "More...  " FormatCount(remaining) " remaining"
        id := this.tv.Add(label, parentId, "Bold")
        node.moreId := id
        this.loadMore[id] := Pager(parentId, "next")
    }

    KeyAt(node, index) {
        if (node.value is Array)
            return String(index)
        return this.Entries(node)[index + 1].key
    }

    ValueAt(node, index) {
        if (node.value is Array)
            return node.value[index + 1]
        return this.Entries(node)[index + 1].value
    }

    Entries(node) {
        if (IsObject(node.entries))
            return node.entries
        list := []
        for k, v in node.value
            list.Push(Kv(k, v))
        node.entries := list
        return list
    }

    IndexOfKey(node, key) {
        if (node.value is Array) {
            if !RegExMatch(key, "^\d+$")
                return -1
            n := Integer(key)
            return (n >= 0 && n < node.total) ? n : -1
        }
        for i, pair in this.Entries(node) {
            if (pair.key == key)
                return i - 1
        }
        return -1
    }

    EnsureChild(parentId, key) {
        node := this.nodes[parentId]
        if (node.childIds.Has(key))
            return true
        if (node.total = 0)
            return false
        idx := this.IndexOfKey(node, key)
        if (idx < 0)
            return false
        inWindow := node.rangeEnd > node.rangeStart && idx >= node.rangeStart && idx < node.rangeEnd
        if (!inWindow) {
            page := (idx // this.pageSize) * this.pageSize
            this.ShowRange(parentId, page, this.pageSize)
        }
        return node.childIds.Has(key)
    }

    ShowDetails(id) {
        if (!this.nodes.Has(id))
            return
        node := this.nodes[id]
        this.pathEdit.Value := node.path
        this.typeText.Text := DescribeValue(node.value)
        this.valueEdit.Value := PreviewValue(node.value)
    }

    MakeLabel(key, isIndex, value) {
        body := Summarize(value)
        if (key != "") {
            shown := isIndex ? ("[" key "]") : OneLine(key, 60)
            body := shown "    " body
        }
        return ClipLabel(body)
    }

    CollapseAll(*) {
        ids := []
        id := 0
        loop {
            id := this.tv.GetNext(id, "Full")
            if !id
                break
            ids.Push(id)
        }
        this.BeginUpdate()
        try {
            for itemId in ids {
                if (this.tv.GetChild(itemId))
                    this.tv.Modify(itemId, "-Expand")
            }
        } finally {
            this.EndUpdate()
        }
        this.SetStatus("Collapsed.")
    }

    FindNext(*) {
        this.Find(1)
    }

    FindPrev(*) {
        this.Find(-1)
    }

    Find(step) {
        if (!this.rootId) {
            this.SetStatus("Parse some JSON first.")
            return
        }
        q := this.searchEdit.Value
        if (q = "") {
            this.SetStatus("Type a key or value to search for, then press Enter or F3.")
            return
        }
        if (q != this.lastQuery) {
            this.SetStatus("Searching...")
            Sleep(15)
            this.lastQuery := q
            this.CollectMatches(q)
            this.matchIndex := 0
        }
        n := this.matches.Length
        if (n = 0) {
            this.SetStatus("No matches.")
            return
        }
        this.matchIndex += step
        if (this.matchIndex > n)
            this.matchIndex := 1
        if (this.matchIndex < 1)
            this.matchIndex := n
        if (!this.Reveal(this.matches[this.matchIndex])) {
            this.SetStatus("Match " this.matchIndex " of " FormatCount(n) " could not be opened.")
            return
        }
        extra := this.matchCapped ? (" Showing the first " FormatCount(n) " matches.") : ""
        this.SetStatus("Match " this.matchIndex " of " FormatCount(n) "." extra)
    }

    CollectMatches(query) {
        this.matches := []
        this.pathBuf := []
        this.matchCapped := false
        value := this.nodes[this.rootId].value
        if (!(value is Map) && !(value is Array)) {
            if (InStr(JsonText(value), query, "Off"))
                this.matches.Push([])
        }
        this.Visit(value, query)
    }

    Visit(value, query) {
        if (this.matches.Length >= this.matchLimit) {
            this.matchCapped := true
            return
        }
        if (value is Map) {
            for k, v in value {
                if (this.matches.Length >= this.matchLimit) {
                    this.matchCapped := true
                    return
                }
                this.pathBuf.Push(PathSeg(k, false))
                this.NoteMatch(k, v, query, true)
                this.Visit(v, query)
                this.pathBuf.Pop()
            }
            return
        }
        if (value is Array) {
            i := 0
            for v in value {
                if (this.matches.Length >= this.matchLimit) {
                    this.matchCapped := true
                    return
                }
                this.pathBuf.Push(PathSeg(i, true))
                this.NoteMatch("", v, query, false)
                this.Visit(v, query)
                this.pathBuf.Pop()
                i++
            }
        }
    }

    NoteMatch(key, value, query, hasKey) {
        hit := hasKey && InStr(key, query, "Off")
        if (!hit && !(value is Map) && !(value is Array))
            hit := InStr(JsonText(value), query, "Off")
        if (hit)
            this.matches.Push(this.pathBuf.Clone())
    }

    Reveal(segs) {
        if (!this.rootId)
            return false
        id := this.rootId
        ok := true
        this.BeginUpdate()
        try {
            for seg in segs {
                if (!this.EnsureChild(id, seg.key)) {
                    ok := false
                    break
                }
                if (this.nodes[id].total > 0)
                    this.tv.Modify(id, "Expand")
                id := this.nodes[id].childIds[seg.key]
            }
        } finally {
            this.EndUpdate()
        }
        if (!ok)
            return false
        this.tv.Modify(id, "Select Vis")
        this.ShowDetails(id)
        return true
    }

    SelectedNode() {
        id := this.tv.GetSelection()
        if (!id || !this.nodes.Has(id))
            return ""
        return this.nodes[id]
    }

    CopyPath(*) {
        node := this.SelectedNode()
        if (!IsObject(node)) {
            this.SetStatus("Select a node first.")
            return
        }
        A_Clipboard := node.path
        this.SetStatus("Copied the path.")
    }

    CopyValue(*) {
        node := this.SelectedNode()
        if (!IsObject(node)) {
            this.SetStatus("Select a node first.")
            return
        }
        val := node.value
        if (val is String) {
            A_Clipboard := val
            this.SetStatus("Copied the string (" FormatCount(StrLen(val)) " characters).")
            return
        }
        if (!(val is Map) && !(val is Array)) {
            A_Clipboard := JsonText(val)
            this.SetStatus("Copied the value.")
            return
        }
        this.SetStatus("Copying value...")
        Sleep(15)
        text := Json.Stringify(val, true, 64, 5000000)
        A_Clipboard := text
        if (Json.truncated)
            this.SetStatus("Copied a truncated value (5,000,000 character limit).")
        else
            this.SetStatus("Copied the value.")
    }

    BeginUpdate() {
        if (this.redrawDepth = 0)
            this.tv.Opt("-Redraw")
        this.redrawDepth++
    }

    EndUpdate() {
        if (this.redrawDepth = 0)
            return
        this.redrawDepth--
        if (this.redrawDepth = 0)
            this.tv.Opt("+Redraw")
    }

    FocusSearch() {
        this.searchEdit.Focus()
        SendMessage(0xB1, 0, -1, this.searchEdit)
    }

    SetStatus(text) {
        this.sb.SetText(text)
    }
}

class TreeNode {
    __New(value, path, key, isIndex) {
        this.value := value
        this.path := path
        this.key := key
        this.isIndex := isIndex
        this.total := ChildCount(value)
        this.rangeStart := 0
        this.rangeEnd := 0
        this.childIds := Map()
        this.entries := ""
        this.placeholder := 0
        this.earlierId := 0
        this.moreId := 0
    }
}

class Kv {
    __New(key, value) {
        this.key := key
        this.value := value
    }
}

class PathSeg {
    __New(key, isIndex) {
        this.key := String(key)
        this.isIndex := isIndex
    }
}

class Pager {
    __New(parent, dir) {
        this.parent := parent
        this.dir := dir
    }
}

class JsonNull {
}

class JsonBool {
    __New(flag) {
        this.flag := flag
    }
}

class JsonNumber {
    __New(literal) {
        this.literal := literal
    }
}

class Json {
    static truncated := false

    static Parse(text) {
        parser := JsonParser(text)
        parser.SkipBom()
        value := parser.ParseValue(0)
        parser.SkipWs()
        if (parser.pos <= parser.len)
            parser.Fail("Unexpected data after the JSON value")
        return value
    }

    static Stringify(value, pretty := true, maxDepth := 32, maxChars := 0) {
        writer := JsonWriter(pretty, maxDepth, maxChars)
        writer.Write(value, 0)
        Json.truncated := writer.truncated
        return writer.out
    }
}

class JsonParser {
    __New(text) {
        this.text := text
        this.len := StrLen(text)
        this.pos := 1
        this.line := 1
        this.col := 1
    }

    ; Code point at a 1-based index. "{" is 123 (byte 7B).
    At(pos) {
        if (pos < 1 || pos > this.len)
            return 0
        return Ord(SubStr(this.text, pos, 1))
    }

    SkipBom() {
        if (this.pos <= this.len && this.Peek() = 0xFEFF)
            this.Advance()
    }

    Peek() {
        if (this.pos > this.len)
            return 0
        return this.At(this.pos)
    }

    Advance() {
        if (this.pos > this.len)
            this.Fail("Unexpected end of JSON")
        ch := this.At(this.pos)
        this.pos++
        if (ch = 13) {
            if (this.pos <= this.len && this.At(this.pos) = 10)
                this.pos++
            this.line++
            this.col := 1
        } else if (ch = 10) {
            this.line++
            this.col := 1
        } else {
            this.col++
        }
        return ch
    }

    SetPos(pos, line, col) {
        this.pos := pos
        this.line := line
        this.col := col
    }

    SkipWs() {
        len := this.len
        pos := this.pos
        line := this.line
        col := this.col
        while (pos <= len) {
            ch := this.At(pos)
            if (ch = 32 || ch = 9) {
                pos++
                col++
            } else if (ch = 10) {
                pos++
                line++
                col := 1
            } else if (ch = 13) {
                pos++
                if (pos <= len && this.At(pos) = 10)
                    pos++
                line++
                col := 1
            } else {
                break
            }
        }
        this.pos := pos
        this.line := line
        this.col := col
    }

    Fail(msg) {
        extra := ""
        ch := this.Peek()
        if (ch >= 32 && ch < 127)
            extra := " near '" Chr(ch) "'"
        else if (ch)
            extra := " U+" Format("{:04X}", ch)
        throw Error(msg extra " (line " this.line ", column " this.col ")", -1)
    }

    ParseValue(depth) {
        static nullInst := JsonNull()
        static trueInst := JsonBool(true)
        static falseInst := JsonBool(false)

        if (depth > 256)
            this.Fail("JSON is nested more than 256 levels deep")
        this.SkipWs()
        if (this.pos > this.len)
            this.Fail("Unexpected end of JSON")
        ch := this.Peek()
        if (ch = 123)
            return this.ParseObject(depth)
        if (ch = 91)
            return this.ParseArray(depth)
        if (ch = 34)
            return this.ParseString()
        if (ch = 116)
            return this.ParseLiteral("true", trueInst)
        if (ch = 102)
            return this.ParseLiteral("false", falseInst)
        if (ch = 110)
            return this.ParseLiteral("null", nullInst)
        if (ch = 45 || (ch >= 48 && ch <= 57))
            return this.ParseNumber()
        this.Fail("Unexpected character")
    }

    ParseObject(depth) {
        this.Advance()
        obj := Map()
        this.SkipWs()
        if (this.Peek() = 125) {
            this.Advance()
            return obj
        }
        loop {
            this.SkipWs()
            if (this.Peek() = 125)
                this.Fail("Trailing commas are not allowed")
            if (this.Peek() != 34)
                this.Fail("Expected a quoted key")
            key := this.ParseString()
            this.SkipWs()
            if (this.Peek() != 58)
                this.Fail("Expected ':' after a key")
            this.Advance()
            obj[key] := this.ParseValue(depth + 1)
            this.SkipWs()
            ch := this.Peek()
            if (ch = 125) {
                this.Advance()
                return obj
            }
            if (ch != 44)
                this.Fail("Expected ',' or '}'")
            this.Advance()
        }
    }

    ParseArray(depth) {
        this.Advance()
        arr := []
        this.SkipWs()
        if (this.Peek() = 93) {
            this.Advance()
            return arr
        }
        loop {
            this.SkipWs()
            if (this.Peek() = 93)
                this.Fail("Trailing commas are not allowed")
            arr.Push(this.ParseValue(depth + 1))
            this.SkipWs()
            ch := this.Peek()
            if (ch = 93) {
                this.Advance()
                return arr
            }
            if (ch != 44)
                this.Fail("Expected ',' or ']'")
            this.Advance()
        }
    }

    ParseLiteral(word, inst) {
        i := 1
        while (i <= StrLen(word)) {
            if (this.Peek() != Ord(SubStr(word, i, 1)))
                this.Fail("Invalid literal")
            this.Advance()
            i++
        }
        return inst
    }

    ParseString() {
        this.Advance()
        len := this.len
        text := this.text
        pos := this.pos
        line := this.line
        col := this.col
        parts := []
        plainStart := pos
        loop {
            if (pos > len) {
                this.SetPos(pos, line, col)
                this.Fail("Unterminated string")
            }
            ch := this.At(pos)
            if (ch = 34) {
                if (pos > plainStart)
                    parts.Push(SubStr(text, plainStart, pos - plainStart))
                pos++
                col++
                break
            }
            if (ch = 92) {
                if (pos > plainStart)
                    parts.Push(SubStr(text, plainStart, pos - plainStart))
                this.SetPos(pos, line, col)
                this.Advance()
                parts.Push(this.ParseEscape())
                pos := this.pos
                line := this.line
                col := this.col
                plainStart := pos
                continue
            }
            if (ch < 32) {
                this.SetPos(pos, line, col)
                this.Fail("Unescaped control character in a string")
            }
            pos++
            col++
        }
        this.SetPos(pos, line, col)
        if (parts.Length = 0)
            return ""
        if (parts.Length = 1)
            return parts[1]
        out := ""
        for part in parts
            out .= part
        return out
    }

    ParseEscape() {
        if (this.pos > this.len)
            this.Fail("Unterminated escape sequence")
        ch := this.Advance()
        switch ch {
            case 34: return '"'
            case 92: return "\"
            case 47: return "/"
            case 98: return Chr(8)
            case 102: return Chr(12)
            case 110: return Chr(10)
            case 114: return Chr(13)
            case 116: return Chr(9)
            case 117: return this.ParseUnicode()
            default: this.Fail("Invalid escape sequence")
        }
    }

    ParseUnicode() {
        high := this.ReadHex(4)
        if (high >= 0xD800 && high <= 0xDBFF) {
            if (this.Peek() != 92)
                this.Fail("Invalid surrogate pair")
            this.Advance()
            if (this.Peek() != 117)
                this.Fail("Invalid surrogate pair")
            this.Advance()
            low := this.ReadHex(4)
            if (low < 0xDC00 || low > 0xDFFF)
                this.Fail("Invalid surrogate pair")
            return Chr(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00))
        }
        if (high >= 0xDC00 && high <= 0xDFFF)
            this.Fail("Unpaired surrogate in a string")
        return Chr(high)
    }

    ReadHex(n) {
        hex := ""
        loop n {
            if (this.pos > this.len)
                this.Fail("Incomplete \u escape")
            ch := this.Advance()
            if !((ch >= 48 && ch <= 57) || (ch >= 65 && ch <= 70) || (ch >= 97 && ch <= 102))
                this.Fail("Invalid hex digit in a \u escape")
            hex .= Chr(ch)
        }
        return Integer("0x" hex)
    }

    ParseNumber() {
        len := this.len
        pos := this.pos
        line := this.line
        col := this.col
        start := pos

        if (pos <= len && this.At(pos) = 45) {
            pos++
            col++
        }
        if (pos > len) {
            this.SetPos(pos, line, col)
            this.Fail("Invalid number")
        }
        ch := this.At(pos)
        if (ch < 48 || ch > 57) {
            this.SetPos(pos, line, col)
            this.Fail("Invalid number")
        }
        if (ch = 48) {
            pos++
            col++
            if (pos <= len) {
                next := this.At(pos)
                if (next >= 48 && next <= 57) {
                    this.SetPos(pos, line, col)
                    this.Fail("Invalid number")
                }
            }
        } else {
            while (pos <= len) {
                ch := this.At(pos)
                if (ch < 48 || ch > 57)
                    break
                pos++
                col++
            }
        }
        if (pos <= len && this.At(pos) = 46) {
            pos++
            col++
            frac := pos
            while (pos <= len) {
                ch := this.At(pos)
                if (ch < 48 || ch > 57)
                    break
                pos++
                col++
            }
            if (pos = frac) {
                this.SetPos(pos, line, col)
                this.Fail("Invalid number")
            }
        }
        if (pos <= len) {
            ch := this.At(pos)
            if (ch = 101 || ch = 69) {
                pos++
                col++
                if (pos <= len) {
                    sign := this.At(pos)
                    if (sign = 43 || sign = 45) {
                        pos++
                        col++
                    }
                }
                exp := pos
                while (pos <= len) {
                    ch := this.At(pos)
                    if (ch < 48 || ch > 57)
                        break
                    pos++
                    col++
                }
                if (pos = exp) {
                    this.SetPos(pos, line, col)
                    this.Fail("Invalid number")
                }
            }
        }
        this.SetPos(pos, line, col)
        return JsonNumber(SubStr(this.text, start, pos - start))
    }
}

class JsonWriter {
    __New(pretty, maxDepth, maxChars) {
        this.pretty := pretty
        this.maxDepth := maxDepth
        this.maxChars := maxChars
        this.out := ""
        this.truncated := false
    }

    Write(value, depth) {
        if (this.truncated)
            return
        if ((value is Map || value is Array) && depth >= this.maxDepth) {
            this.Append(value is Map ? "{...}" : "[...]")
            return
        }
        if (value is Map)
            this.WriteObject(value, depth)
        else if (value is Array)
            this.WriteArray(value, depth)
        else if (value is String)
            this.WriteString(value)
        else
            this.Append(JsonText(value))
    }

    WriteObject(obj, depth) {
        this.Append("{")
        if (obj.Count = 0) {
            this.Append("}")
            return
        }
        first := true
        for k, v in obj {
            if (this.truncated)
                return
            if (!first)
                this.Append(",")
            first := false
            this.Indent(depth + 1)
            this.Append(Quote(k))
            this.Append(this.pretty ? ": " : ":")
            this.Write(v, depth + 1)
        }
        if (this.truncated)
            return
        this.Indent(depth)
        this.Append("}")
    }

    WriteArray(arr, depth) {
        this.Append("[")
        if (arr.Length = 0) {
            this.Append("]")
            return
        }
        first := true
        for v in arr {
            if (this.truncated)
                return
            if (!first)
                this.Append(",")
            first := false
            this.Indent(depth + 1)
            this.Write(v, depth + 1)
        }
        if (this.truncated)
            return
        this.Indent(depth)
        this.Append("]")
    }

    WriteString(s) {
        limit := this.maxChars > 0 ? this.maxChars : StrLen(s)
        cut := StrLen(s) > limit
        if (cut)
            s := SubStr(s, 1, limit)
        this.Append(Quote(s))
        if (cut)
            this.ForceTruncated()
    }

    Indent(depth) {
        if (!this.pretty || this.truncated)
            return
        this.Append("`r`n")
        loop depth
            this.Append("  ")
    }

    Append(s) {
        if (this.truncated)
            return
        if (this.maxChars > 0 && StrLen(this.out) + StrLen(s) > this.maxChars) {
            room := this.maxChars - StrLen(this.out)
            if (room > 0)
                this.out .= SubStr(s, 1, room)
            this.truncated := true
            this.out .= "`r`n... (truncated)"
            return
        }
        this.out .= s
    }

    ForceTruncated() {
        if (this.truncated)
            return
        this.truncated := true
        this.out .= "`r`n... (truncated)"
    }
}

ReadJsonFile(path) {
    ; A raw buffer handed to StrGet was treated as UTF-16, so a file that
    ; starts with byte 7B ("{") was not read as the character "{".
    f := FileOpen(path, "r")
    if !f
        throw Error("Could not open the file")
    b1 := f.ReadUChar()
    b2 := f.ReadUChar()
    f.Close()
    if (b1 = 0xFF && b2 = 0xFE)
        return FileRead(path, "UTF-16")
    if (b1 = 0xFE && b2 = 0xFF)
        return FileRead(path, "CP1201")
    return FileRead(path, "UTF-8")
}

ChildCount(value) {
    if (value is Map)
        return value.Count
    if (value is Array)
        return value.Length
    return 0
}

DescribeValue(value) {
    if (value is Map) {
        n := value.Count
        suffix := n = 1 ? "" : "s"
        return "an object with " FormatCount(n) " key" suffix
    }
    if (value is Array) {
        n := value.Length
        suffix := n = 1 ? "" : "s"
        return "an array with " FormatCount(n) " item" suffix
    }
    if (value is String) {
        n := StrLen(value)
        suffix := n = 1 ? "" : "s"
        return "a string of " FormatCount(n) " character" suffix
    }
    if (value is JsonNumber)
        return "a number"
    if (value is JsonBool)
        return value.flag ? "true" : "false"
    if (value is JsonNull)
        return "null"
    return "a value"
}

Summarize(value) {
    if (value is Map) {
        n := value.Count
        suffix := n = 1 ? " key" : " keys"
        return "{ }  " FormatCount(n) suffix
    }
    if (value is Array) {
        n := value.Length
        suffix := n = 1 ? " item" : " items"
        return "[ ]  " FormatCount(n) suffix
    }
    if (value is String)
        return '"' StrReplace(OneLine(value, 80), '"', '\"') '"'
    return JsonText(value)
}

JsonText(value) {
    if (value is String)
        return value
    if (value is JsonNull)
        return "null"
    if (value is JsonBool)
        return value.flag ? "true" : "false"
    if (value is JsonNumber)
        return value.literal
    return ""
}

PreviewValue(value) {
    if (value is String) {
        if (StrLen(value) > 80000)
            return Quote(SubStr(value, 1, 80000)) "`r`n... (truncated, " FormatCount(StrLen(value)) " characters)"
        return Quote(value)
    }
    if (value is Map || value is Array)
        return Json.Stringify(value, true, 6, 80000)
    return JsonText(value)
}

Quote(s) {
    return '"' EscapeJson(s) '"'
}

EscapeJson(s) {
    if !RegExMatch(s, '[\x00-\x1F"\\]')
        return s
    out := ""
    i := 1
    n := StrLen(s)
    while (i <= n) {
        ch := SubStr(s, i, 1)
        code := Ord(ch)
        if (ch = '"')
            out .= '\"'
        else if (ch = "\")
            out .= "\\"
        else if (code = 8)
            out .= "\b"
        else if (code = 9)
            out .= "\t"
        else if (code = 10)
            out .= "\n"
        else if (code = 12)
            out .= "\f"
        else if (code = 13)
            out .= "\r"
        else if (code < 32)
            out .= "\u" Format("{:04X}", code)
        else
            out .= ch
        i += Max(StrLen(ch), 1)
    }
    return out
}

JoinKey(parent, key) {
    if RegExMatch(key, "^[A-Za-z_][A-Za-z0-9_]*$")
        return parent "." key
    return parent "[" Quote(key) "]"
}

OneLine(s, maxLen) {
    s := StrReplace(s, "`r", " ")
    s := StrReplace(s, "`n", " ")
    s := StrReplace(s, "`t", " ")
    if (StrLen(s) > maxLen)
        s := SubStr(s, 1, maxLen - 3) "..."
    return s
}

ClipLabel(s) {
    s := StrReplace(s, "`r", " ")
    s := StrReplace(s, "`n", " ")
    s := StrReplace(s, "`t", " ")
    if (StrLen(s) > 200)
        s := SubStr(s, 1, 197) "..."
    return StrReplace(s, "&", "&&")
}

FormatCount(n) {
    return RegExReplace(String(n), "(\d)(?=(\d{3})+$)", "$1,")
}

SearchHasFocus() {
    global app
    ctrl := app.gui.FocusedCtrl
    return IsObject(ctrl) && ctrl.Hwnd = app.searchEdit.Hwnd
}

app := JsonTreeApp()
app.Show()

#HotIf WinActive("ahk_id " app.gui.Hwnd)
^Enter:: {
    global app
    app.Parse()
}
^o:: {
    global app
    app.OpenFile()
}
^f:: {
    global app
    app.FocusSearch()
}
F3:: {
    global app
    app.FindNext()
}
+F3:: {
    global app
    app.FindPrev()
}
#HotIf

#HotIf WinActive("ahk_id " app.gui.Hwnd) && SearchHasFocus()
Enter:: {
    global app
    app.Find(1)
}
#HotIf
