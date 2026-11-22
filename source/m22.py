from base import *
rows = ''.join(f'<div style="display:flex;align-items:center;gap:10px;padding:7px 10px;border-radius:9px;background:rgba(255,255,255,.05);margin-bottom:6px"><span style="font-size:14px">{i}</span><div style="flex:1"><div style="font-size:12.5px;font-weight:600">{n}</div><div class="s" style="font-size:11px">{m}</div></div>{p}</div>' for i,n,m,p in [
 ('📌','design-final.fig','Pinned · kept forever','<span style="font-size:13px;color:#fff">📌</span>'),
 ('📌','contract.pdf','Pinned · kept forever','<span style="font-size:13px;color:#fff">📌</span>'),
 ('🖼','screenshot 12.png','Expires in 2 days',''),
 ('📄','notes.txt','Expires in 6 days','')])
inner = '<div style="font-size:13px;display:flex;justify-content:space-between;margin-bottom:10px"><b>Shelf</b><span class="q">auto-clears after a week</span></div>'+rows
body = cap("Open notch · Shelf, pinned items on top") + opened(inner, h=250)
body += cap("Right-click a tile → Pin") + compact('<span>▤ 4</span>','<span>☀︎ 12°</span>', peek='<span>design-final.fig pinned — it won’t expire</span><span class="pill" style="height:18px">Undo</span>', h_scene=96)
open("m22.html","w").write(page("Shelf: pin items so they never expire","Auto-cleanup keeps the shelf fresh; pinned files stay as long as you need them.",body))
