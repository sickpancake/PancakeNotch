from base import *
mon=f'''<div style="background:#2a2a2e;padding:14px 14px 30px;border-radius:16px;width:936px;position:relative">
<div class="scene" style="height:250px;border-radius:6px">{menubar()}
<div class="n" style="--e:6px;width:340px;border-radius:0 0 14px 14px"><div class="ears"><div>♫ {bars()}</div><div class="cam" style="text-align:center;font-size:10px" class="q"></div><div style="display:flex;gap:6px;align-items:center"><span class="ring" style="--p:40%"></span>3:12</div></div></div>
<div style="position:absolute;top:44px;left:50%;transform:translateX(-50%);font-size:11px;color:rgba(255,255,255,.75)">virtual notch on a screen without a camera cutout</div></div>
<div style="position:absolute;bottom:9px;left:50%;transform:translateX(-50%);font-size:11px" class="q">Studio Display (main) · MacBook lid closed</div></div>'''
body=cap("External monitor · same ears, Home and gestures")+mon
body+=cap("Settings › Notch")+'<div class="card" style="width:620px;font-size:13px"><b>Show the notch on</b><div style="display:flex;gap:6px;margin-top:10px"><span class="pill">Built-in display</span><span class="pill" style="background:#f5f5f5;color:#000">Main display</span><span class="pill">Display with the pointer</span></div><div class="note">On screens without a notch, PancakeNotch draws a black notch at the top centre, sized from the menu bar.</div></div>'
open("m11.html","w").write(page("External displays: a notch on your main monitor","Keep PancakeNotch when the MacBook is closed or off to the side.",body))
