from base import *
g='<span class="dot" style="background:#30d158"></span>'
body=cap("Peek · an agent finishes")+compact(g+'<span>Claude</span>','<span>✓ done</span>',peek='<span>Claude Code finished · feat/calendar</span><span class="s">6 files · +214 −37</span>',h_scene=96)
inner=f'''<div style="display:flex;justify-content:space-between;font-size:13px"><span>{g}&nbsp; <b>Claude Code</b> <span class="s">· PancakeNotch</span></span><span class="q">2 min ago</span></div>
<div class="s" style="font-size:12px;margin-top:6px">⎇ feat/calendar &nbsp;·&nbsp; 6 files changed &nbsp;·&nbsp; <span style="color:#fff">+214</span> −37</div>
<div style="font-size:13px;margin-top:6px">“Add EventKit source and meeting link parser”</div>
<div style="display:flex;gap:8px;margin-top:16px"><span class="pill main">Open in Cursor</span><span class="pill">Terminal here</span><span class="pill">Copy summary</span></div>'''
body+=cap("Open notch · Agents, the finished row")+opened(inner,tabs='<span>♫</span><span class="on">✦</span><span>◷</span>')
body+=cap("Home widget · Agents (medium)")+f'<div class="tile" style="background:#000;width:270px;height:104px"><div class="q" style="font-size:11px">AGENTS</div><div style="font-size:13px;margin-top:6px">{g} Claude · done</div><div class="s" style="font-size:12px;margin-top:3px">feat/calendar · +214 −37</div><div class="pill" style="height:20px;margin-top:10px">Open</div></div>'
open("m05.html","w").write(page("Agents: a finished agent shows what changed","Branch, files and line counts from local git, with one-click Open in editor.",body))
