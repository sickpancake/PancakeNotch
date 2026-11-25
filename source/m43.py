from base import *
widget = '''
<div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
 <div class="tile" style="min-height:76px"><div style="display:flex;justify-content:space-between"><b style="font-size:12px">Clipboard</b><span class="q" style="font-size:10px">6 clips</span></div>
   <div style="margin-top:8px;font-size:11px;line-height:1.55"><div>📌 Release checklist</div><div>https://github.com/…</div><div style="color:rgba(255,255,255,.45)">Screenshot.png</div></div></div>
 <div class="tile" style="min-height:76px"><div style="display:flex;justify-content:space-between"><b style="font-size:12px">Shelf</b><span class="q" style="font-size:10px">4 items</span></div><div style="display:flex;gap:4px;margin-top:10px"><span class="pill">file</span><span class="pill">img</span><span class="pill">link</span></div></div>
 <div class="tile"><b style="font-size:12px">Timer</b><div style="font-size:20px;margin-top:8px">4:59</div></div>
 <div class="tile"><b style="font-size:12px">Notes</b><div style="font-size:11px;margin-top:8px;color:rgba(255,255,255,.6)">Launch ideas</div></div>
</div>'''
body = cap("Home · recent copies are one click away") + opened(widget, h=205)
body += cap("Clicking a clip copies it again without opening the Shelf first") + compact('<span class="pill">Shelf</span>', '<span class="pill">Notes</span>', peek='<span><b>Copied</b>&nbsp;<span class="s">Release checklist</span></span><span class="pill" style="height:18px;font-size:11px;padding:0 9px">Pinned</span>')
body += '<div class="note">A new Clipboard Home widget reuses ShelfClipboard.entries and copyClipboardEntry(_:). Small shows the count; medium and large show the newest clips with pinned first. The widget itself opens Shelf › Clipboard.</div>'
open("m43.html","w").write(page("Home: a Clipboard widget","People who reuse copied text, links and images can paste an older clip straight from Home.",body))
