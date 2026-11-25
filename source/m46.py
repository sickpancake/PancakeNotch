from base import *
amber = '#ff9f0a'
home = f'''
<div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
 <div class="tile"><div style="display:flex;justify-content:space-between"><b style="font-size:12px">Timer</b><span class="q" style="font-size:10px">Tea</span></div><div style="display:flex;align-items:center;gap:10px;margin-top:10px"><span class="ring" style="--p:8%;width:28px;height:28px;background:conic-gradient({amber} 8%,rgba(255,255,255,.2) 0)"></span><b style="font-size:22px;color:{amber}">0:42</b></div></div>
 <div class="tile"><b style="font-size:12px">Clock</b><div style="font-size:20px;margin-top:10px">10:04</div></div>
</div>'''
timerpage = f'''
<div style="font-size:11px;color:rgba(255,255,255,.45);margin-bottom:8px">TIMERS</div>
<div class="tile" style="display:flex;align-items:center;gap:10px"><span class="ring" style="--p:8%;width:24px;height:24px;background:conic-gradient({amber} 8%,rgba(255,255,255,.2) 0)"></span><div style="flex:1"><b style="font-size:13px;color:{amber}">Tea · 0:42</b><div class="s" style="font-size:10px">ends 10:05</div></div><span class="pill" style="height:20px;font-size:10px">+1 min</span></div>'''
body = cap("Home · the same last-minute amber as the ear") + opened(home, h=145)
body += cap("Open Timer · running rows use it too") + opened(timerpage, h=125)
body += '<div class="note">v0.5.1 made the compact ear amber under one minute, but TimerRing in Home and the open Timer list still defaults to white. Share TimerEar.tint/_:at: (or a TimerTint helper) so the warning reads the same everywhere.</div>'
open("m46.html","w").write(page("Timer: carry last-minute amber everywhere","People who keep Home or the Timer page open get the same urgent visual cue they already get beside the closed notch.",body))
