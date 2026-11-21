CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,'SF Pro Text',Helvetica,sans-serif;background:#1b1f2a;color:#fff;width:1000px;-webkit-font-smoothing:antialiased}
.page{padding:28px 32px 30px}
h1{font-size:20px;font-weight:600;margin-bottom:4px}
.sub{font-size:13px;color:rgba(255,255,255,.6);margin-bottom:18px}
.row{display:flex;gap:22px;align-items:flex-start;flex-wrap:wrap}
.scene{background:linear-gradient(160deg,#3a4a6b,#6b5a7a 55%,#c08a6a);border-radius:14px;position:relative;overflow:hidden;margin-bottom:6px}
.cap{font-size:12px;color:rgba(255,255,255,.55);margin:14px 0 8px;letter-spacing:.02em;text-transform:uppercase}
.menubar{height:32px;background:rgba(20,20,24,.35);backdrop-filter:blur(10px);display:flex;align-items:center;justify-content:space-between;padding:0 14px;font-size:13px;color:rgba(255,255,255,.92)}
.menubar .l span{margin-right:16px}.menubar .l b{margin-right:18px}
.n{position:absolute;top:0;left:50%;transform:translateX(-50%);background:#000;color:#fff}
.n:before,.n:after{content:"";position:absolute;top:0;width:var(--e);height:var(--e)}
.n:before{left:calc(-1*var(--e));background:radial-gradient(circle at 0 100%,transparent calc(var(--e) - .5px),#000 var(--e))}
.n:after{right:calc(-1*var(--e));background:radial-gradient(circle at 100% 100%,transparent calc(var(--e) - .5px),#000 var(--e))}
.ears{display:flex;justify-content:space-between;align-items:center;height:32px;padding:0 12px;font-size:12px;gap:8px}
.cam{width:185px;flex:none}
.peek{height:24px;display:flex;align-items:center;justify-content:space-between;padding:0 12px;font-size:12px;color:rgba(255,255,255,.85)}
.panel{padding:40px 18px 14px}
.q{color:rgba(255,255,255,.45)}.s{color:rgba(255,255,255,.6)}
.pill{display:inline-flex;align-items:center;gap:5px;height:24px;padding:0 11px;border-radius:12px;background:rgba(255,255,255,.13);font-size:12px;white-space:nowrap}
.main{background:#fff;color:#000;font-weight:600}
.tile{background:rgba(255,255,255,.07);border:1px solid rgba(255,255,255,.07);border-radius:12px;padding:10px 12px}
.ring{width:18px;height:18px;border-radius:50%;background:conic-gradient(#fff var(--p),rgba(255,255,255,.25) 0);display:inline-block;-webkit-mask:radial-gradient(circle,transparent 5.5px,#000 6px)}
.bar{height:4px;border-radius:2px;background:rgba(255,255,255,.16);overflow:hidden}.bar i{display:block;height:100%;background:rgba(255,255,255,.92)}
.tabs{position:absolute;top:8px;left:16px;display:flex;gap:2px}.tabs span{width:28px;height:22px;border-radius:11px;display:flex;align-items:center;justify-content:center;font-size:12px;color:rgba(255,255,255,.55)}.tabs .on{background:rgba(255,255,255,.16);color:#fff}
.win{background:#090909;border:1px solid rgba(255,255,255,.12);border-radius:12px;overflow:hidden;font-family:'SF Pro Rounded',-apple-system,sans-serif}
.win .tb{height:30px;background:#0f0f0f;display:flex;align-items:center;padding:0 12px;gap:7px;border-bottom:1px solid rgba(255,255,255,.085)}
.win .tb i{width:11px;height:11px;border-radius:50%;background:rgba(255,255,255,.2)}
.card{background:rgba(255,255,255,.045);border:1px solid rgba(255,255,255,.085);border-radius:16px;padding:14px 20px}
.dot{display:inline-block;width:7px;height:7px;border-radius:50%}
.note{font-size:12px;color:rgba(255,255,255,.55);margin-top:10px;line-height:1.45}
"""
def menubar(right="100%&nbsp;&nbsp; Fri 10:04"):
    return f'<div class="menubar"><div class="l"><b></b><b>Finder</b><span>File</span><span>Edit</span><span>View</span><span>Go</span></div><div>{right}</div></div>'
def compact(left, right, w=340, peek=None, h_scene=72, extra=""):
    pk = f'<div class="peek">{peek}</div>' if peek else ""
    br = 16 if peek else 14
    return f'''<div class="scene" style="height:{h_scene}px">{menubar()}
<div class="n" style="--e:6px;width:{w}px;border-radius:0 0 {br}px {br}px"><div class="ears"><div style="display:flex;align-items:center;gap:6px">{left}</div><div class="cam"></div><div style="display:flex;align-items:center;gap:6px">{right}</div></div>{pk}</div>{extra}</div>'''
def opened(inner, h=180, w=600, tabs="", h_scene=None):
    hs = h_scene or h+26
    t = f'<div class="tabs">{tabs}</div>' if tabs else ""
    return f'''<div class="scene" style="height:{hs}px">{menubar()}
<div class="n" style="--e:18px;width:{w}px;height:{h}px;border-radius:0 0 26px 26px;box-shadow:0 12px 30px rgba(0,0,0,.45)">{t}<div class="panel">{inner}</div></div></div>'''
def page(title, sub, body):
    return f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body><div class="page"><h1>{title}</h1><div class="sub">{sub}</div>{body}</div></body></html>'
def cap(t): return f'<div class="cap">{t}</div>'
CSS += ".ears{white-space:nowrap}"
def bars():
    return '<span style="display:inline-flex;gap:2px;align-items:end;height:12px">'+''.join(f'<i style="width:3px;height:{h}px;background:#fff;border-radius:1px"></i>' for h in (6,11,8,4))+'</span>'
