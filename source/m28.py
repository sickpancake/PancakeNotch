from base import *
body = cap("Compact · a peek you missed is gone today") + compact('<span>♪ track</span>','<span>80%&nbsp;▮</span>')
body += cap("Expanded · a 'while you were away' row above Home") + opened('''
<div style="font-size:11px;color:rgba(255,255,255,.45);margin-bottom:6px">WHILE YOU WERE AWAY</div>
<div style="display:flex;gap:8px">
 <div class="tile" style="min-width:150px"><div class="q" style="font-size:10px">TIMER · 12m ago</div><div style="font-size:12px;margin-top:4px">Tea is done</div></div>
 <div class="tile" style="min-width:150px"><div class="q" style="font-size:10px">AGENTS · 26m ago</div><div style="font-size:12px;margin-top:4px">Claude finished in PancakeNotch</div></div>
 <div class="tile" style="min-width:150px"><div class="q" style="font-size:10px">NOW PLAYING · 1h ago</div><div style="font-size:12px;margin-top:4px">♪ Song title</div></div>
</div>''', h=150)
body += '<div class="note">Clicking a card opens the notch on that module. The row clears once you have seen it; only peeks while the notch was closed are kept (last ~5).</div>'
open("m28.html","w").write(page("Peeks: a “While you were away” row","People who look away during a 3-second peek see what they missed, and can jump to the module.",body))
