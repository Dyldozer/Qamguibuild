#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode("Input")
SetWorkingDir(A_ScriptDir)

; Password Manager (AutoHotkey v2)
; Standalone Alt+Q menu for logins and links. Config is always the last item.
; Does not include or depend on any other script in this repository.

class PasswordManager {
    static Current := 0

    __New() {
        PasswordManager.Current := this
        this.items := []
        this.sendDelay := 50
        this.vaultPath := A_ScriptDir "\vault.json"
        this.targetHwnd := 0
        this.gui := 0
        this.tv := 0
        this.tvIds := Map()
        this.il := 0
        this.modalOpen := false
        this.saving := false
        this.ctx := 0
        this.sb := 0
        this.detailEdit := 0
        this.showSecrets := 0
        this.delayEdit := 0
        this.btns := []
        this.detailBox := 0
        this.delayLabel := 0
    }

    static ConfigActive() {
        cur := PasswordManager.Current
        if !cur || !cur.gui || cur.modalOpen
            return false
        if !WinActive("ahk_id " cur.gui.Hwnd)
            return false
        try {
            focused := ControlGetFocus("ahk_id " cur.gui.Hwnd)
            return InStr(focused, "SysTreeView")
        } catch {
            return false
        }
    }

    Start() {
        this.Load()
        this.SetupTray()
        Hotkey("!q", this.OnHotkey.Bind(this))
    }

    SetupTray() {
        A_IconTip := "Password Manager — Alt+Q"
        tray := A_TrayMenu
        tray.Delete()
        tray.Add("Open &Config", this.OpenConfig.Bind(this))
        tray.Add()
        tray.Add("&Reload", (*) => Reload())
        tray.Add("E&xit", (*) => ExitApp())
        tray.Default := "Open &Config"
    }

    OnHotkey(*) {
        this.targetHwnd := WinExist("A")
        this.ShowMenu()
    }

    ShowMenu() {
        menuObj := this.BuildMenu(this.items)
        menuObj.Add()
        menuObj.Add("Config", this.OpenConfig.Bind(this))
        try menuObj.SetIcon("Config", A_WinDir "\System32\shell32.dll", 22)
        menuObj.Show()
    }

    BuildMenu(items) {
        menuObj := Menu()
        used := Map()
        if items.Length = 0 {
            menuObj.Add("(empty)", (*) => 0)
            menuObj.Disable("(empty)")
            return menuObj
        }
        for item in items {
            label := this.UniqueLabel(this.MenuLabel(item["name"]), used)
            type := item["type"]
            if type = "submenu" {
                sub := this.BuildMenu(item["items"])
                menuObj.Add(label, sub)
                try menuObj.SetIcon(label, A_WinDir "\System32\shell32.dll", 4)
            } else if type = "link" {
                menuObj.Add(label, this.OnLink.Bind(this, item))
                try menuObj.SetIcon(label, A_WinDir "\System32\shell32.dll", 14)
            } else {
                menuObj.Add(label, this.OnLogin.Bind(this, item))
                try menuObj.SetIcon(label, A_WinDir "\System32\shell32.dll", 48)
            }
        }
        return menuObj
    }

    MenuLabel(name) {
        name := Trim(name)
        if name = ""
            name := "(unnamed)"
        return StrReplace(name, "&", "&&")
    }

    UniqueLabel(label, used) {
        base := label
        n := 1
        while used.Has(StrLower(label)) {
            n++
            label := base " (" n ")"
        }
        used[StrLower(label)] := true
        return label
    }

    OnLogin(item, *) {
        hwnd := this.targetHwnd
        if hwnd && WinExist("ahk_id " hwnd)
            WinActivate("ahk_id " hwnd)
        Sleep(this.sendDelay)
        user := item.Has("username") ? item["username"] : ""
        pass := item.Has("password") ? item["password"] : ""
        useTab := item.Has("useTab") ? item["useTab"] : 1
        if user != ""
            SendText(user)
        if useTab && user != "" && pass != "" {
            Send("{Tab}")
            Sleep(this.sendDelay)
        }
        if pass != ""
            SendText(pass)
    }

    OnLink(item, *) {
        url := this.NormalizeUrl(item.Has("url") ? item["url"] : "")
        if url = "" {
            MsgBox("This link has no URL.", "Password Manager", "Iconx")
            return
        }
        try {
            Run(url)
        } catch as err {
            MsgBox("Could not open the link:`n" err.Message, "Password Manager", "Iconx")
        }
    }

    NormalizeUrl(url) {
        url := Trim(url)
        if url = ""
            return url
        if RegExMatch(url, "i)^[a-z][a-z0-9+\-.]*:")
            return url
        return "https://" url
    }

    Load() {
        this.items := []
        this.sendDelay := 50
        if !FileExist(this.vaultPath)
            return
        try {
            text := FileRead(this.vaultPath, "UTF-8")
            if Trim(text) = ""
                return
            data := VaultJson.Parse(text)
            if !(data is Map)
                throw Error("Vault root must be a JSON object")
            if data.Has("sendDelayMs") && IsNumber(data["sendDelayMs"])
                this.sendDelay := Max(0, Min(2000, Integer(data["sendDelayMs"])))
            if data.Has("items") && data["items"] is Array
                this.items := this.UnpackItems(data["items"])
        } catch as err {
            MsgBox("Could not load vault.json:`n" err.Message, "Password Manager", "Iconx")
            this.items := []
        }
    }

    Save() {
        if this.saving
            return
        this.saving := true
        try {
            if this.delayEdit {
                delayText := Trim(this.delayEdit.Value)
                if RegExMatch(delayText, "^\d+$")
                    this.sendDelay := Max(0, Min(2000, Integer(delayText)))
            }
            payload := Map()
            payload["version"] := 1
            payload["sendDelayMs"] := this.sendDelay
            payload["items"] := this.PackItems(this.items)
            text := VaultJson.Stringify(payload)
            tmp := this.vaultPath ".tmp"
            f := FileOpen(tmp, "w", "UTF-8-RAW")
            if !f
                throw Error("Could not write the vault temp file")
            f.Write(text)
            f.Close()
            FileMove(tmp, this.vaultPath, true)
            if this.sb
                this.sb.SetText("Saved  ·  Alt+Q opens the menu  ·  Config is always last")
        } catch as err {
            if this.sb
                this.sb.SetText("Save failed")
            MsgBox("Could not save vault.json:`n" err.Message, "Password Manager", "Iconx")
        } finally {
            this.saving := false
        }
    }

    PackItems(items) {
        out := []
        for item in items {
            row := Map()
            row["id"] := item["id"]
            row["type"] := item["type"]
            row["name"] := item["name"]
            switch item["type"] {
                case "submenu":
                    row["items"] := this.PackItems(item.Has("items") ? item["items"] : [])
                case "login":
                    row["username"] := this.PackSecret(item.Has("username") ? item["username"] : "")
                    row["password"] := this.PackSecret(item.Has("password") ? item["password"] : "")
                    row["useTab"] := item.Has("useTab") ? (item["useTab"] ? 1 : 0) : 1
                case "link":
                    row["url"] := item.Has("url") ? item["url"] : ""
            }
            out.Push(row)
        }
        return out
    }

    UnpackItems(items) {
        out := []
        if !(items is Array)
            return out
        for item in items {
            if !(item is Map) || !item.Has("type")
                continue
            type := item["type"]
            row := Map()
            row["id"] := item.Has("id") && item["id"] != "" ? item["id"] : this.NewId()
            row["type"] := type
            row["name"] := item.Has("name") ? item["name"] : ""
            switch type {
                case "submenu":
                    row["items"] := this.UnpackItems(item.Has("items") ? item["items"] : [])
                case "login":
                    row["username"] := this.UnpackSecret(item.Has("username") ? item["username"] : "")
                    row["password"] := this.UnpackSecret(item.Has("password") ? item["password"] : "")
                    row["useTab"] := item.Has("useTab") ? (item["useTab"] ? 1 : 0) : 1
                case "link":
                    row["url"] := item.Has("url") ? item["url"] : ""
                default:
                    continue
            }
            out.Push(row)
        }
        return out
    }

    PackSecret(text) {
        if text = ""
            return ""
        return Map("dpapi", Dpapi.Protect(text))
    }

    UnpackSecret(val) {
        if val = "" || !IsSet(val)
            return ""
        if val is String
            return val
        if val is Map {
            if val.Has("dpapi") && val["dpapi"] != ""
                return Dpapi.Unprotect(val["dpapi"])
            if val.Has("plain")
                return val["plain"]
        }
        return ""
    }

    NewId() {
        return Format("{:08x}{:08x}{:08x}", Random(0, 0x7FFFFFFF), Random(0, 0x7FFFFFFF), A_TickCount)
    }

    OpenConfig(*) {
        if this.gui {
            this.RefreshTree()
            this.gui.Show()
            WinActivate("ahk_id " this.gui.Hwnd)
            return
        }
        this.BuildConfigGui()
        this.RefreshTree()
        this.gui.Show("w840 h580")
        this.gui.GetClientPos(, , &w, &h)
        this.Layout(w, h)
    }

    BuildConfigGui() {
        this.gui := Gui("+Resize +MinSize720x480", "Password Manager Config")
        this.gui.SetFont("s9", "Segoe UI")
        this.gui.OnEvent("Close", (*) => this.gui.Hide())
        this.gui.OnEvent("Escape", (*) => this.gui.Hide())
        this.gui.OnEvent("Size", this.OnSize.Bind(this))

        this.tv := this.gui.AddTreeView("w520 h360")
        this.tv.OnEvent("ItemSelect", (*) => this.UpdateDetails())
        this.tv.OnEvent("DoubleClick", this.OnTreeDoubleClick.Bind(this))
        this.tv.OnEvent("ContextMenu", this.OnTreeContext.Bind(this))

        this.il := IL_Create(3)
        if this.il {
            try IL_Add(this.il, A_WinDir "\System32\shell32.dll", 4)
            try IL_Add(this.il, A_WinDir "\System32\shell32.dll", 48)
            try IL_Add(this.il, A_WinDir "\System32\shell32.dll", 14)
            this.tv.SetImageList(this.il)
        }

        this.addSubBtn := this.gui.AddButton("w148 h28", "Add &submenu")
        this.addSubBtn.OnEvent("Click", this.AddSubmenu.Bind(this))
        this.addLoginBtn := this.gui.AddButton("w148 h28", "Add &login")
        this.addLoginBtn.OnEvent("Click", this.AddLogin.Bind(this))
        this.addLinkBtn := this.gui.AddButton("w148 h28", "Add lin&k")
        this.addLinkBtn.OnEvent("Click", this.AddLink.Bind(this))
        this.editBtn := this.gui.AddButton("w148 h28", "&Edit")
        this.editBtn.OnEvent("Click", this.EditSelected.Bind(this))
        this.delBtn := this.gui.AddButton("w148 h28", "&Delete")
        this.delBtn.OnEvent("Click", this.DeleteSelected.Bind(this))
        this.upBtn := this.gui.AddButton("w148 h28", "Move &up")
        this.upBtn.OnEvent("Click", (*) => this.MoveSelected(-1))
        this.downBtn := this.gui.AddButton("w148 h28", "Move &down")
        this.downBtn.OnEvent("Click", (*) => this.MoveSelected(1))
        this.nestBtn := this.gui.AddButton("w148 h28", "&Nest")
        this.nestBtn.OnEvent("Click", this.NestSelected.Bind(this))
        this.unnestBtn := this.gui.AddButton("w148 h28", "U&nnest")
        this.unnestBtn.OnEvent("Click", this.UnnestSelected.Bind(this))

        this.btns := [
            this.addSubBtn, this.addLoginBtn, this.addLinkBtn,
            this.editBtn, this.delBtn, this.upBtn, this.downBtn,
            this.nestBtn, this.unnestBtn
        ]

        this.delayLabel := this.gui.AddText("w148 h20", "Typing delay (ms)")
        this.delayEdit := this.gui.AddEdit("w80 h22 Number", this.sendDelay)
        this.delayEdit.OnEvent("Change", this.OnDelayChange.Bind(this))

        this.detailBox := this.gui.AddGroupBox("w800 h118", "Selected item")
        this.detailEdit := this.gui.AddEdit("ReadOnly Multi -WantReturn VScroll", "")
        this.showSecrets := this.gui.AddCheckbox("h20", "Show secrets")
        this.showSecrets.OnEvent("Click", (*) => this.UpdateDetails())

        this.sb := this.gui.AddStatusBar(, "Alt+Q opens the menu. Config is always the last item.")
        this.sb.SetText("F2 edit · Insert login · Shift+Insert submenu · Ctrl+Insert link · Alt+↑↓ reorder · Alt+←→ nest")

        this.ctx := Menu()
        this.ctx.Add("Add submenu", this.AddSubmenu.Bind(this))
        this.ctx.Add("Add login", this.AddLogin.Bind(this))
        this.ctx.Add("Add link", this.AddLink.Bind(this))
        this.ctx.Add()
        this.ctx.Add("Edit", this.EditSelected.Bind(this))
        this.ctx.Add("Delete", this.DeleteSelected.Bind(this))
        this.ctx.Add()
        this.ctx.Add("Move up", (*) => this.MoveSelected(-1))
        this.ctx.Add("Move down", (*) => this.MoveSelected(1))
        this.ctx.Add("Nest", this.NestSelected.Bind(this))
        this.ctx.Add("Unnest", this.UnnestSelected.Bind(this))
    }

    OnSize(gui, minMax, width, height) {
        if minMax = -1
            return
        this.Layout(width, height)
    }

    Layout(w, h) {
        if w < 200 || h < 200
            return
        pad := 10
        gap := 8
        btnW := 148
        btnH := 28
        measured := 0
        this.sb.GetPos(, , , &measured)
        sbH := (measured >= 16 && measured <= 80) ? measured : 22
        detailH := 118
        btnX := w - pad - btnW
        treeW := btnX - pad - gap
        treeH := h - pad - gap - detailH - sbH - 4
        if treeH < 120
            treeH := 120
        this.tv.Move(pad, pad, treeW, treeH)
        y := pad
        for btn in this.btns {
            btn.Move(btnX, y, btnW, btnH)
            y += btnH + 6
        }
        y += 8
        this.delayLabel.Move(btnX, y, btnW, 18)
        y += 20
        this.delayEdit.Move(btnX, y, 80, 22)

        detailY := pad + treeH + gap
        detailW := w - pad * 2
        this.detailBox.Move(pad, detailY, detailW, detailH)
        this.detailEdit.Move(pad + 12, detailY + 22, detailW - 150, detailH - 32)
        this.showSecrets.Move(pad + detailW - 128, detailY + 22, 116, 22)
    }

    OnDelayChange(*) {
        if this.modalOpen
            return
        delayText := Trim(this.delayEdit.Value)
        if !RegExMatch(delayText, "^\d+$")
            return
        this.sendDelay := Max(0, Min(2000, Integer(delayText)))
        this.Save()
    }

    OnTreeContext(ctrl, item, isRight, x, y) {
        if item
            this.tv.Modify(item, "Select")
        this.ctx.Show()
    }

    OnTreeDoubleClick(ctrl, item) {
        if item
            this.tv.Modify(item, "Select")
        node := this.SelectedNode()
        if !node || node["type"] = "submenu"
            return
        this.EditSelected()
    }

    RefreshTree(selectId := "") {
        if !this.tv
            return
        expanded := this.CollectExpanded()
        if selectId = "" {
            node := this.SelectedNode()
            if node
                selectId := node["id"]
        }
        if selectId != "" {
            found := this.FindById(selectId)
            if found
                this.MarkAncestorsExpanded(found, expanded)
        }
        this.tv.Delete()
        this.tvIds := Map()
        selectTv := 0
        this.AddTreeNodes(0, this.items, expanded, selectId, &selectTv)
        if selectTv
            this.tv.Modify(selectTv, "Select Vis")
        this.UpdateDetails()
    }

    CollectExpanded() {
        expanded := Map()
        item := 0
        loop {
            item := this.tv.GetNext(item, "Full")
            if !item
                break
            if this.tv.Get(item, "Expand") && this.tvIds.Has(item)
                expanded[this.tvIds[item]["id"]] := true
        }
        return expanded
    }

    MarkAncestorsExpanded(node, expanded) {
        loc := this.Locate(node)
        while loc && loc.parent {
            expanded[loc.parent["id"]] := true
            loc := this.Locate(loc.parent)
        }
    }

    AddTreeNodes(parentTv, items, expanded, selectId, &selectTv) {
        for item in items {
            icon := 2
            if item["type"] = "submenu"
                icon := 1
            else if item["type"] = "link"
                icon := 3
            opt := this.il ? ("Icon" icon) : ""
            tvId := this.tv.Add(this.TreeLabel(item), parentTv, opt)
            this.tvIds[tvId] := item
            if item["id"] = selectId
                selectTv := tvId
            if item["type"] = "submenu" {
                this.AddTreeNodes(tvId, item["items"], expanded, selectId, &selectTv)
                if expanded.Has(item["id"])
                    this.tv.Modify(tvId, "Expand")
            }
        }
    }

    TreeLabel(item) {
        name := Trim(item["name"])
        if name = ""
            name := "(unnamed)"
        return name
    }

    SelectedNode() {
        if !this.tv
            return 0
        id := this.tv.GetSelection()
        if !id || !this.tvIds.Has(id)
            return 0
        return this.tvIds[id]
    }

    FindById(id, items := unset) {
        if !IsSet(items)
            items := this.items
        for child in items {
            if child["id"] = id
                return child
            if child["type"] = "submenu" {
                found := this.FindById(id, child["items"])
                if found
                    return found
            }
        }
        return 0
    }

    Locate(node, items := unset, parent := 0) {
        if !IsSet(items)
            items := this.items
        for i, child in items {
            if child["id"] = node["id"]
                return { items: items, index: i, parent: parent }
            if child["type"] = "submenu" {
                found := this.Locate(node, child["items"], child)
                if found
                    return found
            }
        }
        return 0
    }

    InsertTarget(node) {
        if !node
            return { items: this.items, index: this.items.Length + 1 }
        if node["type"] = "submenu"
            return { items: node["items"], index: node["items"].Length + 1 }
        loc := this.Locate(node)
        return { items: loc.items, index: loc.index + 1 }
    }

    AddSubmenu(*) {
        node := this.SelectedNode()
        data := this.ShowSubmenuDialog(Map("name", ""))
        if !data
            return
        data["id"] := this.NewId()
        data["type"] := "submenu"
        data["items"] := []
        target := this.InsertTarget(node)
        target.items.InsertAt(target.index, data)
        this.Save()
        this.RefreshTree(data["id"])
    }

    AddLogin(*) {
        node := this.SelectedNode()
        data := this.ShowLoginDialog(Map("name", "", "username", "", "password", "", "useTab", 1))
        if !data
            return
        data["id"] := this.NewId()
        data["type"] := "login"
        target := this.InsertTarget(node)
        target.items.InsertAt(target.index, data)
        this.Save()
        this.RefreshTree(data["id"])
    }

    AddLink(*) {
        node := this.SelectedNode()
        data := this.ShowLinkDialog(Map("name", "", "url", ""))
        if !data
            return
        data["id"] := this.NewId()
        data["type"] := "link"
        target := this.InsertTarget(node)
        target.items.InsertAt(target.index, data)
        this.Save()
        this.RefreshTree(data["id"])
    }

    EditSelected(*) {
        node := this.SelectedNode()
        if !node
            return
        switch node["type"] {
            case "submenu":
                data := this.ShowSubmenuDialog(node)
                if !data
                    return
                node["name"] := data["name"]
            case "login":
                data := this.ShowLoginDialog(node)
                if !data
                    return
                node["name"] := data["name"]
                node["username"] := data["username"]
                node["password"] := data["password"]
                node["useTab"] := data["useTab"]
            case "link":
                data := this.ShowLinkDialog(node)
                if !data
                    return
                node["name"] := data["name"]
                node["url"] := data["url"]
            default:
                return
        }
        this.Save()
        this.RefreshTree(node["id"])
    }

    DeleteSelected(*) {
        node := this.SelectedNode()
        if !node
            return
        loc := this.Locate(node)
        if !loc
            return
        name := Trim(node["name"])
        if name = ""
            name := "(unnamed)"
        this.gui.Opt("+OwnDialogs")
        extra := ""
        if node["type"] = "submenu" && node["items"].Length
            extra := "`nThis will also delete everything inside it."
        if MsgBox("Delete '" name "'?" extra, "Password Manager", "YesNo Icon?") != "Yes"
            return
        loc.items.RemoveAt(loc.index)
        this.Save()
        this.RefreshTree(loc.parent ? loc.parent["id"] : "")
    }

    MoveSelected(delta) {
        node := this.SelectedNode()
        if !node
            return
        loc := this.Locate(node)
        if !loc
            return
        newIndex := loc.index + delta
        if newIndex < 1 || newIndex > loc.items.Length
            return
        other := loc.items[newIndex]
        loc.items[newIndex] := loc.items[loc.index]
        loc.items[loc.index] := other
        this.Save()
        this.RefreshTree(node["id"])
    }

    NestSelected(*) {
        node := this.SelectedNode()
        if !node
            return
        loc := this.Locate(node)
        if !loc || loc.index <= 1
            return
        prev := loc.items[loc.index - 1]
        if prev["type"] != "submenu"
            return
        loc.items.RemoveAt(loc.index)
        prev["items"].Push(node)
        this.Save()
        this.RefreshTree(node["id"])
    }

    UnnestSelected(*) {
        node := this.SelectedNode()
        if !node
            return
        loc := this.Locate(node)
        if !loc || !loc.parent
            return
        ploc := this.Locate(loc.parent)
        if !ploc
            return
        loc.items.RemoveAt(loc.index)
        ploc.items.InsertAt(ploc.index + 1, node)
        this.Save()
        this.RefreshTree(node["id"])
    }

    UpdateDetails(*) {
        if !this.detailEdit
            return
        node := this.SelectedNode()
        if !node {
            this.detailEdit.Value := "Select an item, or add a submenu / login / link.`r`nNew items go inside the selected submenu, or after the selected item."
            return
        }
        show := this.showSecrets ? this.showSecrets.Value : 0
        switch node["type"] {
            case "submenu":
                n := node["items"].Length
                this.detailEdit.Value := "Name: " node["name"] "`r`nType: Submenu`r`nItems: " n
            case "login":
                user := node.Has("username") ? node["username"] : ""
                pass := node.Has("password") ? node["password"] : ""
                if !show {
                    user := user = "" ? "" : "••••••••"
                    pass := pass = "" ? "" : "••••••••"
                }
                tab := (node.Has("useTab") ? node["useTab"] : 1)
                    ? "Yes — type username, Tab, then password"
                    : "No — type username then password with no Tab"
                this.detailEdit.Value :=
                    "Name: " node["name"]
                    . "`r`nType: Username / password"
                    . "`r`nUse Tab: " tab
                    . "`r`nUsername: " user
                    . "`r`nPassword: " pass
            case "link":
                this.detailEdit.Value := "Name: " node["name"] "`r`nType: Link`r`nURL: " (node.Has("url") ? node["url"] : "")
            default:
                this.detailEdit.Value := ""
        }
    }

    ShowSubmenuDialog(src) {
        dlg := Gui("-MinimizeBox", "Submenu")
        dlg.SetFont("s9", "Segoe UI")
        dlg.AddText("xm w70 h20", "&Name")
        nameEdit := dlg.AddEdit("x+8 yp-2 w260 h22", src.Has("name") ? src["name"] : "")
        okBtn := dlg.AddButton("xm w88 h28 Default", "OK")
        dlg.AddButton("x+8 yp w88 h28", "Cancel").OnEvent("Click", (*) => dlg.Destroy())
        state := { ok: false, name: "" }
        submit := (*) => this.SubmitNameDialog(dlg, nameEdit, state)
        okBtn.OnEvent("Click", submit)
        dlg.OnEvent("Close", (*) => dlg.Destroy())
        dlg.OnEvent("Escape", (*) => dlg.Destroy())
        this.RunModal(dlg)
        if !state.ok
            return 0
        return Map("name", state.name)
    }

    ShowLinkDialog(src) {
        dlg := Gui("-MinimizeBox", "Link")
        dlg.SetFont("s9", "Segoe UI")
        dlg.AddText("xm w70 h20", "&Name")
        nameEdit := dlg.AddEdit("x+8 yp-2 w300 h22", src.Has("name") ? src["name"] : "")
        dlg.AddText("xm w70 h20", "&URL")
        urlEdit := dlg.AddEdit("x+8 yp-2 w300 h22", src.Has("url") ? src["url"] : "")
        okBtn := dlg.AddButton("xm w88 h28 Default", "OK")
        dlg.AddButton("x+8 yp w88 h28", "Cancel").OnEvent("Click", (*) => dlg.Destroy())
        state := { ok: false, name: "", url: "" }
        submit := (*) => this.SubmitLinkDialog(dlg, nameEdit, urlEdit, state)
        okBtn.OnEvent("Click", submit)
        dlg.OnEvent("Close", (*) => dlg.Destroy())
        dlg.OnEvent("Escape", (*) => dlg.Destroy())
        this.RunModal(dlg)
        if !state.ok
            return 0
        return Map("name", state.name, "url", state.url)
    }

    ShowLoginDialog(src) {
        dlg := Gui("-MinimizeBox", "Login")
        dlg.SetFont("s9", "Segoe UI")
        dlg.AddText("xm w80 h20", "&Name")
        nameEdit := dlg.AddEdit("x+8 yp-2 w280 h22", src.Has("name") ? src["name"] : "")
        dlg.AddText("xm w80 h20", "&Username")
        userEdit := dlg.AddEdit("x+8 yp-2 w280 h22", src.Has("username") ? src["username"] : "")
        dlg.AddText("xm w80 h20", "&Password")
        passEdit := dlg.AddEdit("x+8 yp-2 w210 h22 Password", src.Has("password") ? src["password"] : "")
        showChk := dlg.AddCheckbox("x+8 yp+2 w60 h20", "Show")
        showChk.OnEvent("Click", (*) => this.SetPasswordVisible(passEdit, showChk.Value))
        tabChk := dlg.AddCheckbox("xm w360 h22 Checked", "Press &Tab between username and password")
        if src.Has("useTab") && !src["useTab"]
            tabChk.Value := 0
        okBtn := dlg.AddButton("xm w88 h28 Default", "OK")
        dlg.AddButton("x+8 yp w88 h28", "Cancel").OnEvent("Click", (*) => dlg.Destroy())
        state := { ok: false, name: "", username: "", password: "", useTab: 1 }
        submit := (*) => this.SubmitLoginDialog(dlg, nameEdit, userEdit, passEdit, tabChk, state)
        okBtn.OnEvent("Click", submit)
        dlg.OnEvent("Close", (*) => dlg.Destroy())
        dlg.OnEvent("Escape", (*) => dlg.Destroy())
        this.RunModal(dlg)
        if !state.ok
            return 0
        return Map("name", state.name, "username", state.username, "password", state.password, "useTab", state.useTab)
    }

    SubmitNameDialog(dlg, nameEdit, state) {
        name := Trim(nameEdit.Value)
        if name = "" {
            dlg.Opt("+OwnDialogs")
            MsgBox("Name is required.", "Submenu", "Iconx")
            return
        }
        state.ok := true
        state.name := name
        dlg.Destroy()
    }

    SubmitLinkDialog(dlg, nameEdit, urlEdit, state) {
        name := Trim(nameEdit.Value)
        url := Trim(urlEdit.Value)
        if name = "" {
            dlg.Opt("+OwnDialogs")
            MsgBox("Name is required.", "Link", "Iconx")
            return
        }
        if url = "" {
            dlg.Opt("+OwnDialogs")
            MsgBox("URL is required.", "Link", "Iconx")
            return
        }
        state.ok := true
        state.name := name
        state.url := url
        dlg.Destroy()
    }

    SubmitLoginDialog(dlg, nameEdit, userEdit, passEdit, tabChk, state) {
        name := Trim(nameEdit.Value)
        if name = "" {
            dlg.Opt("+OwnDialogs")
            MsgBox("Name is required.", "Login", "Iconx")
            return
        }
        state.ok := true
        state.name := name
        state.username := userEdit.Value
        state.password := passEdit.Value
        state.useTab := tabChk.Value ? 1 : 0
        dlg.Destroy()
    }

    SetPasswordVisible(edit, show) {
        SendMessage(0x00CC, show ? 0 : 0x25CF, 0, edit.Hwnd)
        edit.Redraw()
    }

    RunModal(dlg) {
        this.modalOpen := true
        hwnd := dlg.Hwnd
        if this.gui {
            this.gui.Opt("+Disabled")
            dlg.Opt("+Owner" this.gui.Hwnd)
        }
        dlg.Show()
        WinWaitClose("ahk_id " hwnd)
        if this.gui {
            try this.gui.Opt("-Disabled")
            try WinActivate("ahk_id " this.gui.Hwnd)
        }
        this.modalOpen := false
    }
}

class Dpapi {
    static BlobSize() {
        return A_PtrSize = 8 ? 16 : 8
    }

    static PtrOffset() {
        return A_PtrSize = 8 ? 8 : 4
    }

    static Protect(text) {
        enc := StrPut(text, "UTF-8")
        src := Buffer(enc)
        StrPut(text, src, "UTF-8")
        dataLen := enc - 1
        inBuf := Buffer(dataLen ? dataLen : 1, 0)
        if dataLen
            DllCall("RtlMoveMemory", "ptr", inBuf, "ptr", src, "uptr", dataLen)
        blobIn := Buffer(Dpapi.BlobSize(), 0)
        NumPut("UInt", dataLen, blobIn, 0)
        NumPut("Ptr", inBuf.Ptr, blobIn, Dpapi.PtrOffset())
        blobOut := Buffer(Dpapi.BlobSize(), 0)
        ok := DllCall("Crypt32\CryptProtectData",
            "ptr", blobIn,
            "wstr", "Password Manager",
            "ptr", 0,
            "ptr", 0,
            "ptr", 0,
            "uint", 0,
            "ptr", blobOut,
            "int")
        if !ok
            throw Error("Windows DPAPI encryption failed", -1, A_LastError)
        cb := NumGet(blobOut, 0, "UInt")
        pb := NumGet(blobOut, Dpapi.PtrOffset(), "Ptr")
        if !cb {
            if pb
                DllCall("Kernel32\LocalFree", "ptr", pb)
            return ""
        }
        outBuf := Buffer(cb)
        DllCall("RtlMoveMemory", "ptr", outBuf, "ptr", pb, "uptr", cb)
        DllCall("Kernel32\LocalFree", "ptr", pb)
        return Dpapi.ToBase64(outBuf)
    }

    static Unprotect(b64) {
        buf := Dpapi.FromBase64(b64)
        blobIn := Buffer(Dpapi.BlobSize(), 0)
        NumPut("UInt", buf.Size, blobIn, 0)
        NumPut("Ptr", buf.Ptr, blobIn, Dpapi.PtrOffset())
        blobOut := Buffer(Dpapi.BlobSize(), 0)
        ok := DllCall("Crypt32\CryptUnprotectData",
            "ptr", blobIn,
            "ptr", 0,
            "ptr", 0,
            "ptr", 0,
            "ptr", 0,
            "uint", 0,
            "ptr", blobOut,
            "int")
        if !ok
            throw Error("Windows DPAPI decryption failed. This vault belongs to another Windows user.", -1, A_LastError)
        cb := NumGet(blobOut, 0, "UInt")
        pb := NumGet(blobOut, Dpapi.PtrOffset(), "Ptr")
        if !cb {
            if pb
                DllCall("Kernel32\LocalFree", "ptr", pb)
            return ""
        }
        outBuf := Buffer(cb)
        DllCall("RtlMoveMemory", "ptr", outBuf, "ptr", pb, "uptr", cb)
        DllCall("Kernel32\LocalFree", "ptr", pb)
        return StrGet(outBuf, "UTF-8")
    }

    static ToBase64(buf) {
        flags := 0x40000001
        chars := 0
        if !DllCall("Crypt32\CryptBinaryToStringW", "ptr", buf, "uint", buf.Size, "uint", flags, "ptr", 0, "uint*", &chars)
            throw Error("Base64 encode failed")
        out := Buffer(chars * 2)
        if !DllCall("Crypt32\CryptBinaryToStringW", "ptr", buf, "uint", buf.Size, "uint", flags, "ptr", out, "uint*", &chars)
            throw Error("Base64 encode failed")
        return StrGet(out, "UTF-16")
    }

    static FromBase64(s) {
        flags := 1
        bytes := 0
        if !DllCall("Crypt32\CryptStringToBinaryW", "wstr", s, "uint", 0, "uint", flags, "ptr", 0, "uint*", &bytes, "ptr", 0, "ptr", 0)
            throw Error("Invalid encrypted data")
        buf := Buffer(bytes)
        if !DllCall("Crypt32\CryptStringToBinaryW", "wstr", s, "uint", 0, "uint", flags, "ptr", buf, "uint*", &bytes, "ptr", 0, "ptr", 0)
            throw Error("Invalid encrypted data")
        buf.Size := bytes
        return buf
    }
}

class VaultJson {
    static Parse(text) {
        p := VaultJson.Parser(text)
        value := p.ParseValue()
        p.SkipWs()
        if p.i <= p.n
            p.Fail("Unexpected data after the JSON value")
        return value
    }

    static Stringify(value) {
        w := VaultJson.Writer()
        w.Write(value, 0, "")
        return w.out
    }

    class Parser {
        __New(text) {
            this.s := text
            this.n := StrLen(text)
            this.i := 1
        }

        Peek() {
            return this.i > this.n ? 0 : Ord(SubStr(this.s, this.i, 1))
        }

        Fail(msg) {
            throw Error(msg " (at character " this.i ")")
        }

        SkipWs() {
            loop {
                c := this.Peek()
                if c = 32 || c = 9 || c = 10 || c = 13 || c = 0xFEFF
                    this.i++
                else
                    break
            }
        }

        ParseValue() {
            this.SkipWs()
            c := this.Peek()
            if c = 123
                return this.ParseObject()
            if c = 91
                return this.ParseArray()
            if c = 34
                return this.ParseString()
            if c = 116
                return this.ParseLiteral("true", 1)
            if c = 102
                return this.ParseLiteral("false", 0)
            if c = 110
                return this.ParseLiteral("null", "")
            if c = 45 || (c >= 48 && c <= 57)
                return this.ParseNumber()
            this.Fail("Invalid JSON value")
        }

        ParseLiteral(word, value) {
            if SubStr(this.s, this.i, StrLen(word)) != word
                this.Fail("Expected " word)
            this.i += StrLen(word)
            return value
        }

        ParseObject() {
            this.i++
            obj := Map()
            this.SkipWs()
            if this.Peek() = 125 {
                this.i++
                return obj
            }
            loop {
                this.SkipWs()
                if this.Peek() != 34
                    this.Fail("Expected a string key")
                key := this.ParseString()
                this.SkipWs()
                if this.Peek() != 58
                    this.Fail("Expected ':'")
                this.i++
                obj[key] := this.ParseValue()
                this.SkipWs()
                c := this.Peek()
                if c = 44 {
                    this.i++
                    continue
                }
                if c = 125 {
                    this.i++
                    return obj
                }
                this.Fail("Expected ',' or '}'")
            }
        }

        ParseArray() {
            this.i++
            arr := []
            this.SkipWs()
            if this.Peek() = 93 {
                this.i++
                return arr
            }
            loop {
                arr.Push(this.ParseValue())
                this.SkipWs()
                c := this.Peek()
                if c = 44 {
                    this.i++
                    continue
                }
                if c = 93 {
                    this.i++
                    return arr
                }
                this.Fail("Expected ',' or ']'")
            }
        }

        ParseString() {
            this.i++
            out := ""
            loop {
                if this.i > this.n
                    this.Fail("Unterminated string")
                c := this.Peek()
                if c = 34 {
                    this.i++
                    return out
                }
                if c = 92 {
                    this.i++
                    e := this.Peek()
                    if !e
                        this.Fail("Unterminated escape")
                    this.i++
                    switch e {
                        case 34: out .= '"'
                        case 92: out .= "\"
                        case 47: out .= "/"
                        case 98: out .= "`b"
                        case 102: out .= "`f"
                        case 110: out .= "`n"
                        case 114: out .= "`r"
                        case 116: out .= "`t"
                        case 117:
                            hex := SubStr(this.s, this.i, 4)
                            if !RegExMatch(hex, "i)^[0-9a-f]{4}$")
                                this.Fail("Invalid Unicode escape")
                            this.i += 4
                            out .= Chr(Integer("0x" hex))
                        default:
                            this.Fail("Invalid escape")
                    }
                    continue
                }
                if c < 32
                    this.Fail("Unescaped control character")
                out .= SubStr(this.s, this.i, 1)
                this.i++
            }
        }

        ParseNumber() {
            start := this.i
            isFloat := false
            if this.Peek() = 45
                this.i++
            c := this.Peek()
            if c = 48
                this.i++
            else if c >= 49 && c <= 57 {
                while this.Peek() >= 48 && this.Peek() <= 57
                    this.i++
            } else
                this.Fail("Invalid number")
            if this.Peek() = 46 {
                isFloat := true
                this.i++
                if this.Peek() < 48 || this.Peek() > 57
                    this.Fail("Invalid number")
                while this.Peek() >= 48 && this.Peek() <= 57
                    this.i++
            }
            c := this.Peek()
            if c = 101 || c = 69 {
                isFloat := true
                this.i++
                c := this.Peek()
                if c = 43 || c = 45
                    this.i++
                if this.Peek() < 48 || this.Peek() > 57
                    this.Fail("Invalid number")
                while this.Peek() >= 48 && this.Peek() <= 57
                    this.i++
            }
            lit := SubStr(this.s, start, this.i - start)
            try {
                return isFloat ? Float(lit) : Integer(lit)
            } catch {
                return Float(lit)
            }
        }
    }

    class Writer {
        __New() {
            this.out := ""
        }

        Indent(depth) {
            this.out .= "`r`n"
            loop depth
                this.out .= "  "
        }

        Write(val, depth, key) {
            if key = "useTab" {
                this.out .= val ? "true" : "false"
                return
            }
            if val is Map
                this.WriteMap(val, depth)
            else if val is Array
                this.WriteArray(val, depth)
            else if val is String
                this.out .= VaultJson.Quote(val)
            else if val is Integer
                this.out .= String(val)
            else if val is Float
                this.out .= Format("{:.15g}", val)
            else
                this.out .= "null"
        }

        WriteMap(obj, depth) {
            this.out .= "{"
            if obj.Count = 0 {
                this.out .= "}"
                return
            }
            first := true
            for k, v in obj {
                if !first
                    this.out .= ","
                first := false
                this.Indent(depth + 1)
                this.out .= VaultJson.Quote(k is String ? k : String(k))
                this.out .= ": "
                this.Write(v, depth + 1, k is String ? k : String(k))
            }
            this.Indent(depth)
            this.out .= "}"
        }

        WriteArray(arr, depth) {
            this.out .= "["
            if arr.Length = 0 {
                this.out .= "]"
                return
            }
            first := true
            for v in arr {
                if !first
                    this.out .= ","
                first := false
                this.Indent(depth + 1)
                this.Write(v, depth + 1, "")
            }
            this.Indent(depth)
            this.out .= "]"
        }
    }

    static Quote(s) {
        out := '"'
        i := 1
        len := StrLen(s)
        while i <= len {
            ch := SubStr(s, i, 1)
            c := Ord(ch)
            switch c {
                case 34: out .= '\"'
                case 92: out .= "\\"
                case 8: out .= "\b"
                case 12: out .= "\f"
                case 10: out .= "\n"
                case 13: out .= "\r"
                case 9: out .= "\t"
                default:
                    if c < 32
                        out .= Format("\u{:04x}", c)
                    else
                        out .= ch
            }
            i++
        }
        return out . '"'
    }
}

app := PasswordManager()
app.Start()

#HotIf PasswordManager.ConfigActive()
F2:: PasswordManager.Current.EditSelected()
Delete:: PasswordManager.Current.DeleteSelected()
Insert:: PasswordManager.Current.AddLogin()
+Insert:: PasswordManager.Current.AddSubmenu()
^Insert:: PasswordManager.Current.AddLink()
!Up:: PasswordManager.Current.MoveSelected(-1)
!Down:: PasswordManager.Current.MoveSelected(1)
!Left:: PasswordManager.Current.UnnestSelected()
!Right:: PasswordManager.Current.NestSelected()
#HotIf
