from base import *
body = cap("Home edit · drag a widget to the page edge to move it across pages") + opened('''
<div style="display:flex;gap:8px;align-items:center">
 <div class="tile" style="width:100px;height:64px"><div class="q" style="font-size:10px">CLOCK</div></div>
 <div class="tile" style="width:100px;height:64px"><div class="q" style="font-size:10px">BATTERY</div></div>
 <div class="tile" style="width:100px;height:64px;border-style:dashed;opacity:.5"><div class="q" style="font-size:10px">TIMER</div></div>
</div>
<div style="position:absolute;right:14px;top:50%;transform:translateY(-50%);text-align:center">
 <div class="pill" style="border:1px dashed rgba(255,255,255,.5);background:rgba(255,255,255,.06)">→ page 2</div>
 <div class="q" style="font-size:10px;margin-top:4px">drop zone</div>
</div>''', h=130)
body += '<div class="note">While dragging in edit mode, hovering the left/right page edge for ~0.4s flips the page (same motion as a swipe) with the widget still held; dropping lands it on the new page. Today you must drop, turn the page, pick it up again.</div>'
open("m31.html","w").write(page("Home editor: drag widgets across pages","People with several Home pages rearrange in one gesture instead of drop-page-pickup.",body))
