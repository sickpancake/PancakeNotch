from base import *
body = cap("Timer ear · over a minute left") + compact('<span class="ring" style="--p:60%"></span><span>4:12</span>','<span>80%&nbsp;▮</span>')
body += cap("Timer ear · under a minute, the ring and digits turn amber") + compact('<span class="ring" style="--p:92%;background:conic-gradient(#f5a623 var(--p),rgba(255,255,255,.25) 0)"></span><span style="color:#f5a623">0:48</span>','<span>80%&nbsp;▮</span>')
body += '<div class="note">Pure color change in TimerEars.swift when remaining < 60s — same shapes, same space, respects Reduce Motion (no pulsing). People running short timers get the urgency cue without opening the notch.</div>'
open("m32.html","w").write(page("Timer: last-minute color in the ear","A 60-second heads-up for people timing tea, talks or pomodoros.",body))
