from base import *
mic='<span style="display:inline-flex;align-items:center;gap:4px"><span class="dot" style="background:#ff9f0a"></span>🎙︎</span>'
cam='<span style="display:inline-flex;align-items:center;gap:4px"><span class="dot" style="background:#30d158"></span>Cam</span>'
body=cap("Compact · on a call (mic and camera in use, music in the other spot)")+compact(mic+'&nbsp;'+cam,'<span>♫ '+bars()+'</span>')
body+=cap("Peek · when the mic turns on")+compact(mic,'',peek='<span>Microphone is on</span>',h_scene=96)
w='<div class="row">'+'<div class="tile" style="background:#000;width:130px;height:104px"><div class="q" style="font-size:11px">IN USE</div><div style="margin-top:10px;font-size:13px">'+mic+' &nbsp;On</div><div style="margin-top:8px;font-size:13px" class="s">Cam &nbsp;Off</div></div>'
w+='<div class="card" style="width:420px;font-size:13px"><b>Show beside the notch</b><div style="margin-top:10px;display:flex;gap:6px"><span class="pill">Microphone</span><span class="pill">Camera</span><span class="pill" style="background:rgba(255,255,255,.3)">Both</span><span class="pill">Neither</span></div><div class="note">Uses system "device in use" notifications. No permission prompt, no polling.</div></div></div>'
body+=cap("Home widget (small) and setting")+w
open("m03.html","w").write(page("Mic and camera in use beside the notch","A light right next to the camera, where people already look.",body))
