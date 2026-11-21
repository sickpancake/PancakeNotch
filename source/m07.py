from base import *
t=lambda txt,c=1,r=1:f'<div class="tile" style="grid-column:span {c};grid-row:span {r};background:#000;font-size:12px">{txt}</div>'
grid='<div style="display:grid;grid-template-columns:repeat(4,96px);grid-auto-rows:64px;gap:8px">'+t("◷ Timer")+t("✦ Agents<br><span class='s'>2 working</span>",2)+t("AI Usage<div class='bar' style='margin-top:8px'><i style='width:62%;background:#30d158'></i></div>")+t("Battery<br><span class='s'>100%</span>")+t("Statistics",2)+t("Keep Awake")+'</div>'
menu='<div class="card" style="width:170px;padding:8px;font-size:13px">'+''.join(f'<div style="padding:6px 10px;border-radius:7px;{"background:rgba(255,255,255,.1)" if a else ""}">{n}{" ✓" if a else ""}</div>' for n,a in [("Work",1),("Evening",0),("Travel",0)])+'<div style="padding:6px 10px" class="s">+ New profile…</div></div>'
win=f'''<div class="win" style="width:936px"><div class="tb"><i></i><i></i><i></i><span class="s" style="font-size:12px;margin-left:10px">PancakeNotch · Home</span></div><div style="padding:20px 24px">
<div style="display:flex;align-items:center;gap:10px;font-size:13px;margin-bottom:16px"><b style="font-size:17px">Home</b><span style="flex:1"></span><span class="s">Profile</span><span class="pill">Work ▾</span><span class="pill">⟳ Auto: weekdays 9:00–18:00</span></div>
<div style="display:flex;gap:24px">{menu}<div>{grid}</div></div></div></div>'''
body=cap("App window · Home editor with profiles")+win
body+=cap("Evening profile · switched automatically at 18:00")+opened('<div style="display:grid;grid-template-columns:repeat(4,1fr);gap:8px">'+t("♫ Now Playing<br><span class='s'>Song — Artist</span>",2)+t("Battery<br><span class='s'>64%</span>")+t("Clock<br><b style='font-size:16px'>18:02</b>")+'</div>',h=150)
open("m07.html","w").write(page("Home profiles","Different Home layouts for work and evening, switched by hand or by time / power.",body))
