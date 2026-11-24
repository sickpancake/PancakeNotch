from base import *
body = cap("Expanded · Shelf › Clipboard, after relaunching PancakeNotch") + opened('''
<div class="q" style="font-size:11px;margin-bottom:6px">PINNED — KEPT ACROSS LAUNCHES</div>
<div class="tile" style="display:flex;align-items:center;gap:8px;margin-bottom:4px"><span>📌</span><span style="font-size:12px">https://github.com/sickpancake/PancakeNotch/pull/144</span><span class="s" style="margin-left:auto">pinned Mon</span></div>
<div class="tile" style="display:flex;align-items:center;gap:8px;margin-bottom:10px"><span>📌</span><span style="font-size:12px">staging.pancake.internal/admin</span><span class="s" style="margin-left:auto">pinned Fri</span></div>
<div class="q" style="font-size:11px;margin-bottom:6px">RECENT</div>
<div class="tile" style="font-size:12px;margin-bottom:4px">The release notes draft…</div>
<div class="tile" style="font-size:12px">AGENTS.md rule 2</div>''', h=200)
body += '<div class="note">Pinned clipboard entries are written into the Shelf store (they already have pinned ShelfItems underneath); on launch they re-enter the history. Unpinned entries keep clearing on quit, exactly as today.</div>'
open("m37.html","w").write(page("Clipboard: pinned clips survive a restart","Clipboard-history users who pin snippets and links they reuse every day.",body))
