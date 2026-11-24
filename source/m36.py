from base import *
body = cap("Expanded · Agents page, Devin cloud session waiting for its next message") + opened('''
<div class="tile" style="margin-bottom:8px">
<div style="display:flex;align-items:center;gap:8px;margin-bottom:6px">
<span class="dot" style="background:#f2c94c"></span><b style="font-size:13px">Devin · fix onboarding copy</b>
<span class="s" style="margin-left:auto">needs you</span></div>
<div class="s" style="font-size:12px;margin-bottom:8px">Should the new tooltip mention the notch, or keep it generic?</div>
<div style="display:flex;gap:6px;align-items:center">
<span class="pill">Stop</span><span class="pill" style="background:rgba(255,255,255,.22);font-weight:600">Continue</span>
<span style="flex:1;height:24px;border-radius:12px;background:rgba(255,255,255,.09);border:1px solid rgba(255,255,255,.15);display:flex;align-items:center;padding:0 11px;font-size:12px;color:rgba(255,255,255,.4)">Reply to Devin…</span>
<span class="pill main">Send</span></div></div>''', h=150)
body += '<div class="note">The field appears beside Continue/Stop only while a cloud session waits for input. Return or Send posts the text through the same call quickReply uses today (DevinCloudAPI.message); the row flips back to working when the session resumes.</div>'
open("m36.html","w").write(page("Agents: type a reply to a waiting cloud session","Users supervising Devin cloud sessions who need more than Continue and Stop.",body))
