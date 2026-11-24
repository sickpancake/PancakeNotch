from base import *
body = cap("Compact · hovering the +n count lists the hidden modules") + compact('<span class="pill">🎵</span>', '<span class="pill"><b>9:58</b>&nbsp;<span class="pill" style="background:rgba(255,255,255,.22);padding:0 7px">+2</span></span>',
  extra='''<div style="position:absolute;top:40px;right:24px;background:rgba(10,10,12,.92);border:1px solid rgba(255,255,255,.14);border-radius:12px;padding:8px 10px;font-size:12px;min-width:150px;box-shadow:0 8px 24px rgba(0,0,0,.5)">
<div style="padding:3px 6px;display:flex;justify-content:space-between;gap:12px"><span>Notes</span><span class="s">3 notes</span></div>
<div style="padding:3px 6px;display:flex;justify-content:space-between;gap:12px"><span>Keep Awake</span><span class="s">on</span></div>
<div class="s" style="padding:5px 6px 2px;font-size:11px">Click the count for Home</div></div>''', h_scene=160)
body += '<div class="note">Resting the pointer on the +n chip (pointerOverEarOverflow already detects this) pops a small menu naming each displaced module, in EarAllocator order. Clicking a name opens that module straight away — the same target tabs-only navigation picks today.</div>'
open("m40.html","w").write(page("Ear overflow: hover the +n to see what didn't fit","Users with more active modules than ear space, checking what's hidden without opening Home.",body))
