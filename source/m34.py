from base import *
body = cap("Expanded · number keys switch the open module") + opened('''
<div style="display:flex;gap:6px;margin-bottom:8px">
<span class="pill" style="background:rgba(255,255,255,.22)">1 Shelf</span><span class="pill">2 Notes</span><span class="pill">3 Timer</span><span class="pill">4 Now Playing</span><span class="pill">5 Agents</span>
</div>
<div class="q" style="font-size:11px">SHELF</div><div style="font-size:13px;margin-top:6px">Drop files, links or text here</div>''', h=140)
body += '<div class="note">In handleKey(_:), digits 1–9 select the module at that position in the arranged order (the order from Module Menu). Shown as a hint row on first use; modules keep their own keys first (handleKey already gives the module first shot).</div>'
open("m34.html","w").write(page("Notch: number keys jump between modules","Keyboard users switch module pages without mousing up to the tabs.",body))
