from pathlib import Path
from PIL import Image
import shutil
ROOT=Path(__file__).resolve().parents[1]
GEN=Path(r'C:\Users\linvisxie\.codex\generated_images\01a12374-ae46-7552-ad65-5bdc38457258')
for name,source in [('bg_env_classroom_exam','exec-240d9935-945c-4593-b2cd-a7ef884131bf.png'),
                    ('bg_env_corridor_convergence','exec-47cab6e8-3a43-4bd5-829b-7a1d01217b51.png')]:
    shutil.copy2(GEN/source, ROOT/'tools/source_art'/('generated_'+source))
    im=Image.open(GEN/source).convert('RGB').resize((1920,1080),Image.Resampling.LANCZOS)
    im.save(ROOT/'assets/art/environments'/(name+'.png'))
