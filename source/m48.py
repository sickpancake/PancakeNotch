from base import *
home = '''
<div style="display:grid;grid-template-columns:1.25fr 1fr;gap:10px">
 <div class="tile"><div style="display:flex;justify-content:space-between"><b style="font-size:12px">Notes</b><span class="q" style="font-size:10px">4 notes</span></div>
  <div style="margin-top:8px;font-size:11px;line-height:1.7"><div>📌 Launch checklist</div><div style="background:rgba(255,255,255,.13);border-radius:6px;padding:1px 5px;margin:1px -5px">Ideas for v0.5.2</div><div>Books to read</div></div></div>
 <div class="tile"><b style="font-size:12px">Timer</b><div style="font-size:20px;margin-top:10px">9:58</div></div>
</div>'''
notes = '''
<div style="display:flex;gap:12px">
 <div style="width:150px;font-size:11px;line-height:1.8;color:rgba(255,255,255,.6)"><div>Launch checklist</div><div style="color:#fff;background:rgba(255,255,255,.13);border-radius:6px;padding-left:5px;margin-left:-5px">Ideas for v0.5.2</div><div>Books to read</div></div>
 <div class="tile" style="flex:1;min-height:82px"><div class="q" style="font-size:10px">IDEAS FOR V0.5.2</div><div style="font-size:12px;margin-top:6px;line-height:1.45">Power module mockup<br>Clipboard widget<br>ACUs on agent rows</div></div>
</div>'''
body = cap("Home · click the exact note, not just the Notes module") + opened(home, h=145)
body += cap("Notes opens with that note selected") + opened(notes, h=135)
body += '<div class="note">Large Notes widgets already render up to four titles. Give each row its own click/VoiceOver action that calls NotesModule.select(_:) before opening the module; clicks on padding still open Notes as they do today.</div>'
open("m48.html","w").write(page("Notes widget: open the note you clicked","People with several notes skip the list scan and land directly in the note they meant.",body))
