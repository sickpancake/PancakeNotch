from base import *
body = cap("Compact · the battery tile sits in the ear") + compact('<span>♪ track</span>','<span>24%&nbsp;▮</span>')
body += cap("At 20% (and again at 10%) · a plug-in peek") + compact('<span>♪ track</span>','<span>19%&nbsp;▮</span>', peek='<span>🔌 Battery 19% — plug in soon</span><span class="q">Battery</span>', h_scene=96)
body += '<div class="note">Reuses peek(_:for:) and the charge feed already driving the Battery widget and Keep Awake’s low-battery cutoff. Fires once per charge cycle per threshold; skipped while Do Not Disturb-style quieting is on (#83).</div>'
open("m33.html","w").write(page("Battery: a low-charge peek at 20% and 10%","Laptop users away from a charger get warned before the Mac dies — without keeping a battery app in the menu bar.",body))
