from base import *
body = cap("Shelf · a corner tag on items that will auto-clear") + opened('''
<div class="q" style="font-size:11px;margin-bottom:6px">SHELF</div>
<div style="display:flex;gap:10px">
 <div class="tile" style="width:120px;height:70px;position:relative"><div style="font-size:11px">report.pdf</div><span style="position:absolute;top:6px;right:6px;font-size:9px" class="pill">2d</span></div>
 <div class="tile" style="width:120px;height:70px;position:relative"><div style="font-size:11px">sketch.png</div><span style="position:absolute;top:6px;right:6px;font-size:9px" class="pill">6d</span></div>
 <div class="tile" style="width:120px;height:70px;position:relative"><div style="font-size:11px">invoice.pdf</div><span style="position:absolute;top:6px;right:6px;font-size:9px" class="pill">📌</span></div>
</div>''', h=140)
body += '<div class="note">Shown only when Settings › Shelf › auto-clear is on. “2d”/“6d” counts down to the cutoff; pinned items get the pin mark instead. Silent expiry (#109 added pinning) becomes visible.</div>'
open("m30.html","w").write(page("Shelf: days-left badge on expiring items","People using auto-clear see which items are about to disappear before they do.",body))
