from base import *
rows = '''
<div style="display:flex;gap:18px;align-items:center">
  <div style="position:relative;width:74px;height:74px;border-radius:50%;background:conic-gradient(#fff 0 76%,rgba(255,255,255,.18) 76% 100%);display:flex;align-items:center;justify-content:center">
    <div style="width:56px;height:56px;border-radius:50%;background:#000;display:flex;align-items:center;justify-content:center;font-size:17px;font-weight:700">76%</div>
  </div>
  <div style="flex:1">
    <div style="font-size:16px;font-weight:650">On battery</div>
    <div class="s" style="font-size:12px;margin-top:3px">About 3 h 40 min left · Condition Normal</div>
    <div style="display:flex;gap:6px;margin-top:12px"><span class="pill main">Open Battery Settings</span><span class="pill">Keep Awake settings</span></div>
  </div>
</div>
<div style="display:flex;gap:8px;margin-top:16px">
  <div class="tile" style="flex:1"><div class="q" style="font-size:10px">POWER SOURCE</div><div style="font-size:12px;margin-top:4px">Battery</div></div>
  <div class="tile" style="flex:1"><div class="q" style="font-size:10px">LOW POWER MODE</div><div style="font-size:12px;margin-top:4px">Off · opens macOS settings</div></div>
</div>'''
body = cap("Expanded · a Power module for the Mac's own battery") + opened(rows, h=175)
body += cap("Compact · charge and charging state can live beside the notch") + compact('<span class="pill">76% ▮</span>', '<span class="pill">☕</span>')
body += '<div class="note">The existing PowerState/IOKit watcher grows into a module: glanceable charge in the ear, detail and a System Settings jump in the open notch. The Home Battery widget can open it instead of being inert.</div>'
open("m42.html","w").write(page("Power: the Mac's battery in the notch","MacBook users on battery see charge, time left and power controls where v0.5.1's plug-in warnings already live.",body))
