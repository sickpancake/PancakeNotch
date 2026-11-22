from base import *
body = cap("Compact · today, only the dial") + compact('<span class="ring" style="--p:42%"></span>','<span>☀︎ 12°</span>')
body += cap("After · the dial plus the minutes left") + compact('<span class="ring" style="--p:42%"></span><span>25m</span>','<span>☀︎ 12°</span>')
body += '<div class="note">KeepAwakeEar already draws the countdown dial for a timed session; add the rounded “25m” beside it when the ear is wide enough (it hides on a shared ear).</div>'
open("m26.html","w").write(page("Keep Awake: minutes left in the ear","The dial shows a session is running; the text says how long without opening the page.",body))
