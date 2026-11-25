from base import *
strip = '''<div class="scene" style="height:150px;background:#050507">
<div style="position:absolute;inset:0;background:linear-gradient(180deg,#111,#020202);display:flex;align-items:center;justify-content:center;color:rgba(255,255,255,.18);font-size:38px;font-weight:700">FULL-SCREEN VIDEO</div>
<div class="n" style="--e:6px;width:340px;border-radius:0 0 16px 16px;box-shadow:0 8px 28px rgba(0,0,0,.7)"><div class="peek" style="height:28px"><span><b>Battery 10%</b>&nbsp;<span class="s">Plug in soon</span></span><span class="pill" style="height:18px;font-size:11px;padding:0 9px">Open</span></div></div>
</div>'''
settings = '''<div class="win" style="width:430px"><div class="tb"><i></i><i></i><i></i></div><div class="card" style="margin:16px"><b style="font-size:13px">Keep Awake</b><div style="display:flex;justify-content:space-between;align-items:center;margin-top:12px;font-size:12px"><span>Show battery warnings in full screen</span><span class="pill main" style="height:20px">On</span></div><div class="q" style="font-size:11px;margin-top:6px">A short strip can appear over a full-screen app, like a finished timer.</div></div></div>'''
body = cap("Full screen · the warning can still reach you") + strip
body += cap("Keep Awake settings · the user stays in control") + settings
body += '<div class="note">v0.5.1 battery warnings use requestPeek(..., revealsInFullScreen: false). Offer the Timer-style choice for the 20% and 10% warnings so a movie, game or presentation does not hide a time-sensitive power warning.</div>'
open("m45.html","w").write(page("Battery warnings: allow them in full screen","People watching full-screen video or playing games still hear the 20% and 10% plug-in reminders.",body))
