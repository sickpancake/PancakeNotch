from base import *
rows = '''
<div style="font-size:11px;color:rgba(255,255,255,.45);margin-bottom:8px">AGENTS</div>
<div style="display:flex;flex-direction:column;gap:8px">
 <div class="tile" style="display:flex;align-items:center;gap:9px"><span class="dot" style="background:#ff9f0a"></span><div style="flex:1"><b style="font-size:12px">Fix onboarding copy</b><div class="s" style="font-size:10px">Devin cloud · waiting for you</div></div><span class="pill" style="height:19px;font-size:10px">2.4 ACUs</span></div>
 <div class="tile" style="display:flex;align-items:center;gap:9px"><span class="dot" style="background:#30d158"></span><div style="flex:1"><b style="font-size:12px">Refresh readme screenshots</b><div class="s" style="font-size:10px">Devin cloud · working · PR #153</div></div><span class="pill" style="height:19px;font-size:10px">5.1 ACUs</span></div>
 <div class="tile" style="display:flex;align-items:center;gap:9px;opacity:.72"><span class="dot" style="background:#fff"></span><div style="flex:1"><b style="font-size:12px">Local refactor</b><div class="s" style="font-size:10px">Claude Code · working</div></div></div>
</div>'''
body = cap("Expanded · cost sits on the Devin cloud row it belongs to") + opened(rows, h=175)
body += '<div class="note">DevinCloudSession already decodes acusConsumed and AI Usage already totals it. Carry the same value onto AgentThread so the row, widget and VoiceOver can say what this session has used while it is still running.</div>'
open("m44.html","w").write(page("Agents: show a Devin session's ACUs","People supervising cloud agents can spot an expensive session before they decide whether to continue or stop it.",body))
