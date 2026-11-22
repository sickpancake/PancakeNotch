from base import *
inner = '''<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px"><b style="font-size:13px">Notes</b><span class="q">8 notes</span></div>
<div style="display:flex;align-items:center;gap:7px;background:rgba(255,255,255,.08);border-radius:8px;padding:6px 10px;margin-bottom:10px"><span class="q">⌕</span><span style="font-size:12px">groceries</span><span style="margin-left:auto" class="q">⌘F</span></div>
<div style="display:flex;flex-direction:column;gap:6px">'''
inner += ''.join(f'<div class="tile" style="padding:8px 12px"><div style="font-size:12px"><span style="background:rgba(255,255,255,.18);border-radius:3px;padding:0 2px">groceries</span>{rest}</div><div class="s" style="font-size:11px;margin-top:3px">{meta}</div></div>' for rest,meta in [(" for Saturday","Pinned · edited 2h ago"),(" list — shared with Alex","Yesterday")])
inner += '</div><div class="note">Filters titles and body text; ⌘F jumps straight to the field.</div>'
body = cap("Open notch · Notes with a search field") + opened(inner, h=210, tabs='<span>♫</span><span class="on">▤</span><span>⏱</span><span>▦</span>')
open("m17.html","w").write(page("Notes: a search field in the list","Filter as you type instead of scrolling — the list already keeps pinned first.",body))
