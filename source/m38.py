from base import *
body = cap("Expanded · Shelf › Clipboard, ⌘F filters the history") + opened('''
<div style="display:flex;align-items:center;gap:6px;height:26px;border-radius:13px;background:rgba(255,255,255,.09);border:1px solid rgba(255,255,255,.15);padding:0 11px;margin-bottom:10px">
<span class="s">⌕</span><span style="font-size:12px">github</span><span class="s" style="margin-left:auto">Esc</span></div>
<div class="tile" style="font-size:12px;margin-bottom:4px">https://<b>github</b>.com/sickpancake/PancakeNotch/pull/144<span class="s" style="float:right">2m ago</span></div>
<div class="tile" style="font-size:12px;margin-bottom:4px">https://<b>github</b>.com/sickpancake/PancakeNotch/issues/98<span class="s" style="float:right">1h ago</span></div>
<div class="tile" style="font-size:12px"><b>github</b> token rotation runbook<span class="s" style="float:right">pinned</span></div>''', h=170)
body += '<div class="note">Same pattern as Notes search (NotesSearchField): ⌘F focuses the field, every word must match, pinned entries stay first, arrows + Return pick a match, Esc clears. A Clipboard search toggle lives in Shelf settings next to Remember what I copy.</div>'
open("m38.html","w").write(page("Clipboard: a search field in the history","Heavy clipboard users digging through dozens of recent copies.",body))
