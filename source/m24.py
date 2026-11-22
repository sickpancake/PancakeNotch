from base import *
rows = ''.join(f'<div style="display:flex;align-items:center;gap:10px;padding:7px 10px;border-radius:9px;background:rgba(255,255,255,.05);margin-bottom:6px"><span style="font-size:14px">{i}</span><div style="flex:1"><div style="font-size:12.5px;font-weight:600">{n}</div><div class="s" style="font-size:11px">{m}</div></div></div>' for i,n,m in [
 ('🖼','screenshot 12.png','just now · pasted'),
 ('🔗','github.com/sickpancake','just now · pasted'),
 ('📄','notes.txt','2 days ago')])
inner = '<div style="font-size:13px;display:flex;justify-content:space-between;margin-bottom:10px"><b>Shelf</b><span class="q">⌘V to paste</span></div>'+rows+'<div class="note">⌘V while the Shelf is open adds the clipboard — files, images, links, text — like a drop.</div>'
body = cap("Open notch · ⌘V pastes into the Shelf") + opened(inner, h=260)
body += cap("Same clipboard, no dragging required") + compact('<span>▤ 3</span>','<span>☀︎ 12°</span>', peek='<span>2 items pasted</span><span class="pill" style="height:18px">View</span>', h_scene=96)
open("m24.html","w").write(page("Shelf: ⌘V pastes the clipboard","Keyboard users add what they copied without reaching for the pointer.",body))
