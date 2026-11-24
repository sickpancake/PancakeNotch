from base import *
body = cap("Compact · two named timers running") + compact('<span class="pill">🎵</span>', '<span class="pill" style="background:rgba(255,255,255,.16)">Pasta <b>2:41</b>&nbsp;<span class="s">+2</span></span>')
body += cap("Today the same ear shows only the countdown — which timer is anyone\'s guess") + compact('<span class="pill">🎵</span>', '<span class="pill"><span class="ring" style="--p:70%"></span>&nbsp;<b>2:41</b>&nbsp;<span class="s">+2</span></span>')
body += '<div class="note">When TimerCenter.timer is named, the ear reads "Pasta 2:41" (name truncates at 12 chars; unnamed timers look exactly as now). Applies to the countdown and end-time ear styles; ring-only keeps the ring.</div>'
open("m39.html","w").write(page("Timer: the ear names the timer that's ending","Users running several named timers who can't tell which countdown is in the ear.",body))
