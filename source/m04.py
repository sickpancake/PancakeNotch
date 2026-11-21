from base import *
bat=lambda p:f'<span style="display:inline-block;width:46px" class="bar"><i style="width:{p}%"></i></span>'
body=cap("Peek · AirPods connect")+compact('<span>🎧︎</span>','<span>82%</span>',peek=f'<span>🎧︎ &nbsp;Lawrence’s AirPods Pro</span><span style="display:flex;gap:6px;align-items:center">L 82% · R 80% {bat(82)}</span>',h_scene=96)
rows=[("🎧︎","AirPods Pro",82),("🖱︎","Magic Mouse",34),("⌨︎","Magic Keyboard",90)]
w='<div class="row"><div class="tile" style="background:#000;width:270px;height:104px"><div class="q" style="font-size:11px">DEVICES</div>'+''.join(f'<div style="display:flex;justify-content:space-between;align-items:center;font-size:12px;margin-top:6px"><span>{i} {n}</span><span style="display:flex;gap:6px;align-items:center" class="s">{p}% {bat(p)}</span></div>' for i,n,p in rows)+'</div>'
w+='<div class="tile" style="background:#000;width:130px;height:104px"><div class="q" style="font-size:11px">BATTERY</div><div style="font-size:22px;font-weight:600;margin-top:8px">100%</div><div class="s" style="font-size:12px">Mac · charging</div></div></div>'
body+=cap("Home widget (medium) next to the existing Battery widget")+w
body+=cap("Peek · a device is running low")+compact('<span>🖱︎</span>','<span>9%</span>',peek='<span>Magic Mouse battery is low</span><span class="s">9%</span>',h_scene=96)
open("m04.html","w").write(page("AirPods and Bluetooth devices","A connect peek and a battery widget for headphones, mice and keyboards.",body))
