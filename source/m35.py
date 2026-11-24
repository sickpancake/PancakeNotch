from base import *
body = cap("Expanded · Notes page, note open") + opened('''
<div style="display:flex;gap:6px;margin-bottom:10px;align-items:center">
<span class="pill">Pin</span><span class="pill">Copy Text</span><span class="pill">Delete</span>
<span class="pill" style="background:rgba(255,255,255,.22);font-weight:600">Send to Shelf</span>
</div>
<div class="q" style="font-size:11px">MEETING NOTES</div>
<div style="font-size:13px;margin-top:6px;line-height:1.5">Ship mockups for the +n hover list<br>Ask about clipboard pins surviving quit<br>Timer ear should name the timer</div>''', h=170)
body += cap("The note lands on the Shelf as a text file, ready to drag out or AirDrop") + compact('<span class="pill">Shelf</span>', '<span class="pill">Notes</span>', peek='<span><b>Shelf</b></span><span class="s">Meeting notes.md · added</span>')
body += '<div class="note">Send to Shelf writes the note as a .md file item on the Shelf (kind .file, first line = file name), then peeks a confirmation. Undo deletes the Shelf item; the note itself is never touched.</div>'
open("m35.html","w").write(page("Notes: send a note to the Shelf","Users who jot in Notes and then need the text as a file — to drag into a chat, AirDrop, or convert.",body))
