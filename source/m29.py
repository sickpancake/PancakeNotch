from base import *
body = cap("Settings · a shortcut row per module") + '''
<div class="win" style="max-width:520px"><div class="tb"><i></i><i></i><i></i><span class="s" style="font-size:11px;margin-left:8px">Settings · Shortcuts</span></div>
<div class="card" style="margin:14px">
<div style="display:flex;justify-content:space-between;font-size:13px;padding:8px 0;border-bottom:1px solid rgba(255,255,255,.08)"><span>Open / close the notch</span><span class="pill">⌃⌘N</span></div>
<div style="display:flex;justify-content:space-between;font-size:13px;padding:8px 0;border-bottom:1px solid rgba(255,255,255,.08)"><span>Shelf</span><span class="pill">⌃⌘1</span></div>
<div style="display:flex;justify-content:space-between;font-size:13px;padding:8px 0;border-bottom:1px solid rgba(255,255,255,.08)"><span>Notes</span><span class="pill">⌃⌘2</span></div>
<div style="display:flex;justify-content:space-between;font-size:13px;padding:8px 0"><span>Timer</span><span class="pill" style="color:rgba(255,255,255,.5)">Record…</span></div>
</div></div>'''
body += cap("Result · the notch opens straight on that module") + opened('<div class="q" style="font-size:11px">SHELF</div><div style="font-size:13px;margin-top:6px">Drop files, links or text here</div>', h=110)
body += '<div class="note">Each module gets an optional recordable shortcut (same recorder as the notch toggle). Pressing it opens the notch expanded on that module — no hover, no page hunting.</div>'
open("m29.html","w").write(page("Shortcuts: jump straight to a module","Keyboard-first users open Shelf, Notes or Timer in one keystroke instead of opening the notch then switching.",body))
