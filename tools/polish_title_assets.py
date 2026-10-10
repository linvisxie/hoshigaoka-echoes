"""Import attributed external display assets; downloads stay under D:/星丘基础."""
from pathlib import Path
import shutil,json
ROOT=Path(__file__).resolve().parents[1]
source=Path('D:/星丘基础/downloads/ui-polish')
for folder in ['assets/fonts','assets/licenses','assets/art/ui/menu']:
    (ROOT/folder).mkdir(parents=True,exist_ok=True)
shutil.copy2(source/'NotoSerifCJKsc-Regular.otf',ROOT/'assets/fonts')
shutil.copy2(source/'NotoSansCJKsc-Regular.otf',ROOT/'assets/fonts')
shutil.copy2(source/'FONT_LICENSE.txt',ROOT/'assets/licenses/NotoSerifCJK-OFL.txt')
shutil.copy2(source/'ICON_LICENSE.txt',ROOT/'assets/licenses/Lucide-ISC-MIT.txt')
for name in ['settings','log-out','play','sparkles']:
    text=(source/(name+'.svg')).read_text(encoding='utf8').replace('currentColor','#eeeaff')
    (ROOT/'assets/art/ui/menu'/(name+'.svg')).write_text(text,encoding='utf8')
# The full ledger also records audio and generated concept derivatives; never overwrite it.
print('Imported Noto display/body fonts and Lucide title icons; see docs/v3_round3_external_assets.json')
