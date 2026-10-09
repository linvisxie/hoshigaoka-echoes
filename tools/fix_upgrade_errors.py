from pathlib import Path
p = Path(__file__).resolve().parents[1] / 'scripts/domain/battle/in_battle_upgrades.gd'
s = p.read_text(encoding='utf-8')

# 把局部 errs 改为写入 u.load_errors，让校验错误真的能被调用方读到
assert 'var errs: Array[String] = []' in s
s = s.replace('	var errs: Array[String] = []\n', '', 1)
n = s.count('errs.append(')
s = s.replace('errs.append(', 'u.load_errors.append(')
p.write_text(s, encoding='utf-8')
print('load_errors now populated at', n, 'sites')
