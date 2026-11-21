#!/bin/bash
cd ~/reports/mock
for f in "$@"; do python3 $f.py && "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=1000,1500 --screenshot=$PWD/$f.png file://$PWD/$f.html 2>/dev/null >/dev/null
python3 - "$f.png" <<'P'
import sys; from PIL import Image
p=sys.argv[1]; im=Image.open(p).convert("RGB"); w,h=im.size; bg=im.getpixel((5,h-5)); px=im.load()
y=h-1
while y>0 and all(px[x,y]==bg for x in range(0,w,7)): y-=1
im.crop((0,0,w,min(h,y+60))).save(p, optimize=True)
P
done
