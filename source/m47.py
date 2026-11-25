from base import *
inner = '''
<div style="position:relative;height:86px">
 <div style="display:flex;gap:3px;margin-top:2px">
  <span class="pill" style="height:22px;padding:0 8px">⌂</span><span class="pill" style="height:22px;padding:0 8px;background:rgba(255,255,255,.24)">▰</span><span class="pill" style="height:22px;padding:0 8px">♪</span><span class="pill" style="height:22px;padding:0 8px">✦</span><span class="pill" style="height:22px;padding:0 8px">⏱</span>
 </div>
 <div style="position:absolute;left:42px;top:31px;background:rgba(35,35,37,.98);border:1px solid rgba(255,255,255,.14);border-radius:7px;padding:6px 9px;font-size:11px;box-shadow:0 5px 18px rgba(0,0,0,.4)">Shelf — press <b>1</b></div>
 <div style="margin-top:38px" class="q">SHELF</div>
</div>'''
body = cap("Expanded · tooltips teach the new number keys") + opened(inner, h=125)
body += '<div class="note">The v0.5.1 shortcut is only documented in Help and the Modules page. Append the arranged number to each tab\'s tooltip and VoiceOver hint (“Shelf — press 1”, Home is 0) when number-key switching is available; keep the hint out of compact ear accessibility text.</div>'
open("m47.html","w").write(page("Number keys: show the shortcut in module tooltips","Keyboard users discover 1–9 and 0 without opening Help or memorizing the Modules page.",body))
