"""Samples the dominant colour of each official League of Legends ranked emblem.

    python3 -m venv venv && venv/bin/pip install pillow
    mkdir emblems && for t in iron bronze silver gold platinum emerald diamond master grandmaster challenger; do
      curl -so emblems/emblem-$t.png https://raw.communitydragon.org/latest/plugins/rcp-fe-lol-static-assets/global/default/images/ranked-emblem/emblem-$t.png; done
    venv/bin/python tool/tier_colors/sample_emblems.py

Method: centre crop; keep opaque pixels that are not shadow (V < 0.45) or a white specular highlight; pick the
hue sector (24 sectors) with the most pixels (grey pixels count less); average the most vivid third (S x V) of
that sector and its neighbours. Only colours are used; the badge artwork in the app stays original.
"""
import colorsys, collections
from PIL import Image
tiers="iron bronze silver gold platinum emerald diamond master grandmaster challenger".split()
def lum(c):
    def f(v):
        v/=255
        return v/12.92 if v<=0.03928 else ((v+0.055)/1.055)**2.4
    return 0.2126*f(c[0])+0.7152*f(c[1])+0.0722*f(c[2])
def contrast(a,b):
    la,lb=lum(a),lum(b); return (max(la,lb)+0.05)/(min(la,lb)+0.05)
body=(0x1C,0x22,0x30)
for t in tiers:
    im=Image.open(f"emblems/emblem-{t}.png").convert("RGBA"); w,h=im.size
    im=im.crop((w//2-250,h//2-300,w//2+250,h//2+300))
    px=[]
    for r,g,b,a in im.get_flattened_data():
        if a<230: continue
        hh,s,v=colorsys.rgb_to_hsv(r/255,g/255,b/255)
        if v<0.45 or (v>0.93 and s<0.15): continue
        px.append((hh,s,v,(r,g,b)))
    # hue histogram weighted by saturation*value, 24 hue sectors; low-saturation tiers handled by the weight too
    hist=collections.Counter()
    for hh,s,v,_ in px: hist[int(hh*24)%24]+=1 if s>0.08 else 0.35
    top=max(hist,key=hist.get)
    sect=[p for p in px if abs((int(p[0]*24)%24)-top) in (0,1,23)]
    sect.sort(key=lambda p:p[1]*p[2],reverse=True)
    sect=sect[:max(50,len(sect)//3)]
    c=tuple(round(sum(p[3][i] for p in sect)/len(sect)) for i in range(3))
    print(f"{t:12s} #{c[0]:02X}{c[1]:02X}{c[2]:02X} n={len(sect)} contrast={contrast(c,body):.2f}")
