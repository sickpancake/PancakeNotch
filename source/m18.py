from base import *
body = cap("Compact · a song change peeks for a fixed 4 seconds") + compact(bars()+'<span>Now Playing</span>','<span>12:34</span>', peek='<span>♫ Midnight Rain — Taylor Swift</span><span class="q">4s</span>', h_scene=96)
body += cap("Hovering the strip holds it — leave and it counts down") + compact(bars()+'<span>Now Playing</span>','<span>12:34</span>', peek='<span>♫ Midnight Rain — Taylor Swift &nbsp;<span style="display:inline-block;width:11px;height:11px;border-radius:50%;border:1.5px solid #fff;vertical-align:-1px"></span></span><span class="q">held</span>', h_scene=96)
body += '<div class="note" style="max-width:560px">The timer only starts when the pointer leaves the strip, so you always have time to read it — and clicking still opens the module.</div>'
open("m18.html","w").write(page("Peek strips: hold while you hover","A peek no longer vanishes mid-read — it stays until your pointer leaves.",body))
