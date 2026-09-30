# QAM XML Import

Standalone AutoHotkey v2 tool. It does not include or call any other script in this repo.

It reads an XML export, changes only two things, writes a new file, and can upload that file the same way the browser does.

## What it changes

1. The first `<QAM_Mapping view="Mappings">`, the last `</QAM_Mapping>`, and everything between them are replaced. Both tags are included. The text in the box (or in `MappingReplacement.txt`) is inserted exactly in their place. Until you replace it, that text is `PLACEHOLDER`.
2. The number inside each `<Source_ID>...</Source_ID>` in the finished file is replaced with the Source ID you type. Whitespace around the number stays. Anything that is not that number stays.

Bytes outside those edits are copied as they are. The original XML is not overwritten. The new file is saved next to it as `<name>.modified.xml`.

Run it on a fresh export. When you add the real mapping text, include the `<QAM_Mapping view="Mappings">` and `</QAM_Mapping>` tags in that text if the file should still contain them. A second run treats the first opening tag and the last closing tag in the file as the block to replace again.

## What it uploads

`Rewrite and Upload` sends the rewritten XML as one HTTP POST.

```
Content-Type: multipart/form-data; boundary=...

--boundary
Content-Disposition: form-data; name="Import"; filename="your-file.xml"
Content-Type: text/xml

(rewritten XML bytes)
--boundary--
```

`filename` is the upload filename in the window, which starts as the name of the file you picked. The form field name is `Import`.

The part `Content-Type` defaults to `text/xml`. Uncheck **Send part type** to send only the `Content-Disposition` line. You can also type another type, including `text/xml; charset=UTF-8`, if the browser request uses that.

## Setup

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Run `QamXmlImport.ahk`.
3. Choose the XML file and type the new Source ID (digits only).
4. Put the real mapping text in the replacement box when you have it. Closing the window, or rewriting, saves that box to `MappingReplacement.txt`.
5. For upload, enter the URL from the browser request. Type the username and password in Authorization. The request sends `Authorization: Basic` plus the Base64 encoding of `username:password`. If the site is already logged in, copy the request's `Cookie` and `Referer` too. Extra lines such as `X-CSRF-Token: ...` go in Extra headers, one `Name: value` per line.

The URL, username, password, cookie, and the other boxes are stored in `QamXmlImport.ini` next to the script. The password and cookie are plain text. That file is not part of the project. Leave both Authorization boxes empty to send the request without that header.

TLS certificate errors are ignored by default so a device page with a self-signed certificate still accepts the upload. Uncheck that box for a public site with a normal certificate.

## Assumptions

These are the choices the script makes where the browser request was not fully specified:

- The new Source ID is the number you type. It is not looked up anywhere.
- The upload URL is the one you type.
- The body is the rewritten XML, not a zip. The field name is `Import`. The part `Content-Type` is sent only while **Send part type** is checked.
- A logged-in session can be supplied by the Authorization username and password, and by pasting `Cookie`, `Referer`, and any other request headers.
- `Source_ID` numbers inside the old mapping block disappear with that block. Numbers in the new text, and numbers outside the block, are updated.
- The opening tag must match `<QAM_Mapping view="Mappings">` exactly. The block runs through the last `</QAM_Mapping>` in the file, and both tags are part of what is replaced.
- The file encoding can be UTF-8, UTF-16 LE, UTF-16 BE, windows-1252, or ISO-8859-1. Any other declared encoding is left byte-for-byte, and the replacement text then has to be ASCII.

## Check the rewriter

`QamXmlImport.ahk /selftest` runs the built-in checks and does not open the window. It exits 0 when they pass.
