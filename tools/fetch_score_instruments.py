"""Fetch six CC0 VSCO 2 CE instruments from the upstream repository, outside the game."""
from pathlib import Path
import json, urllib.request, urllib.parse
ASSETS=[('Brass/F Horn/stac/MOHorn_stac_C3_v3_rr1.wav','horn_stac_C3.wav'),('Strings/Cello Section/spic/spic_C3_v2_RR1.wav','cello_spic_C3.wav'),('Percussion/Marimba/Marimba_hit_Outrigger_C4_loud_01.wav','marimba_C4.wav'),('Strings/Harp/KSHarp_A4_mf.wav','harp_A4.wav'),('Woodwinds/Flute/stac/LDFlute_stac_A4_v3_rr1.wav','flute_stac_A4.wav'),('Woodwinds/Flute/susvib/LDFlute_susvib_A4_v1_1.wav','flute_sus_A4.wav')]
if __name__=='__main__':
    bank=Path('D:/星丘基础/downloads/ui-polish/VSCO2-orchestra')
    for path,name in ASSETS:
        target=bank/name
        if not target.exists():
            url='https://raw.githubusercontent.com/sgossner/VSCO-2-CE/master/'+urllib.parse.quote(path)
            with urllib.request.urlopen(url,timeout=30) as response: target.write_bytes(response.read())
        print(name,target.stat().st_size,flush=True)
    (bank/'additional_sources.json').write_text(json.dumps(ASSETS,indent=2))
