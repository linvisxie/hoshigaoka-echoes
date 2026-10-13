"""Build the reviewed English catalog; never modify gameplay data or IDs."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
catalog = {}
for kind in ('ui', 'data'):
    sources = json.loads((ROOT / f'tools/localization_{kind}.json').read_text(encoding='utf-8'))
    for line in (ROOT / f'tools/localization_{kind}_en.txt').read_text(encoding='utf-8').splitlines():
        index, target = line.split('\t', 1)
        catalog[sources[int(index)]] = target.replace('\\n', '\n')
catalog.update({
    '语言': 'Language', '中文 / English': '中文 / English',
    '音量、显示与语言  /  修改后立即生效': 'Audio, display & language / Changes take effect immediately',
    '学生手册': 'Student Handbook', '放课后 · 校园': 'After School · Campus',
    '雨宫澪在这里': 'Mio is here', '前往其他区域': 'Explore other areas',
    '留意那些还没有被听见的声音。': 'Listen for the voices still unheard.',
    '放课后观测记录': 'After-School Observations',
    '上段': 'Upper', '中段': 'Middle', '下段': 'Lower',
    '上路': 'Upper', '中路': 'Middle', '下路': 'Lower',
    '武器': 'Weapons', '饰品': 'Accessories', '校园纪念物': 'Campus Mementos',
    '未知类型': 'Unknown Type', '优秀': 'Fine', '稀有': 'Rare',
    '高一': 'Year 1', '高二': 'Year 2', '高三': 'Year 3',
    '澪': 'Mio', '悠真': 'Yuma', '结衣': 'Yui', '凛': 'Rin', '纱良': 'Sara', '千夏': 'Chinatsu',
    '需要等级 Lv.%d（当前 Lv.%d）': 'Requires Lv.%d (current Lv.%d)',
    '冷却 %.0f 秒': 'Cooldown %.0fs',
    '下一阶需 Lv.%d': 'Next requires Lv.%d',
    '武器类型不匹配：这件装备仅适用于使用弓箭的角色': 'Weapon mismatch: only bow users can equip this item.',
    '战斗已经结束': 'The battle has ended', '战斗已结束': 'The battle has ended',
    '实验装置尚未就绪': 'Experimental device is not ready',
    '请选择合法空部署格': 'Choose a valid empty deployment tile',
    '技能冷却中、已蓄力或受到沉默': 'Skill cooling down, already charged or silenced',
    '请选择空部署格放置实验装置': 'Choose an empty tile for the experimental device',
    '技能效果尚未实现': 'This skill effect is not available',
    '可部署': 'Ready to deploy', '非法部署格': 'Invalid deployment tile',
    '该格已被占用': 'This tile is occupied', '本关不可使用该角色': 'Character unavailable in this stage',
    '该角色已在场': 'Character already deployed',
    '再部署冷却中（剩余 %.1f 秒）': 'Redeployment cooldown (%.1fs left)',
    '场上已达同时部署上限（%d 名）': 'Deployment limit reached (%d allies)',
    '已撤退': 'Retreated', '该角色不在场上': 'Character is not deployed',
    '该角色已无法战斗': 'Character is incapacitated', '未知原因(%d)': 'Unknown reason (%d)',
    '未知路线(%d)': 'Unknown lane (%d)', '进行中': 'In Progress', '胜利': 'Victory', '失败': 'Defeat',
    '物理': 'Physical', '特殊': 'Special', '未知(%d)': 'Unknown (%d)',
    '投入数量必须为正': 'Choose a positive amount', '未知角色：%s': 'Unknown character: %s',
    '未知学习记录：%s': 'Unknown Study Record: %s',
    '学习记录不足（需要 %d，持有 %d）': 'Not enough Study Records (need %d, owned %d)',
    '已达当前等级上限 Lv.%d（需要突破）': 'Level cap Lv.%d reached (ascension required)',
    '未知角色': 'Unknown character', '材料不足：%s': 'Not enough materials: %s',
    '材料扣除失败': 'Could not spend materials',
    '权益 ID 为空': 'Reward ID is empty',
    '权益不在待领取列表中（可能已兑现）': 'Reward is not pending (it may already be claimed)',
    '该权益类型（%s）不由装备系统兑现': 'Reward type (%s) cannot be claimed as equipment',
    '装备模板不存在：%s': 'Equipment definition missing: %s', '存档不可用': 'Save unavailable',
    '存档为空': 'Save is empty', '实例创建失败': 'Could not create item',
    '权益兑现失败（已回滚实例）': 'Could not claim reward (item rolled back)',
    '落盘失败（内存已回滚）': 'Save failed (changes rolled back)', '参数为空': 'Empty argument',
    '装备实例不存在': 'Equipment item not found', '模板槽位非法：%s': 'Invalid equipment slot: %s',
    '参数非法': 'Invalid argument', '该槽位没有装备': 'This slot is empty',
    '实例 ID 为空': 'Item ID is empty',
    '该装备不可强化（纪念物或未配置强化上限）': 'This item cannot be enhanced',
    '已达强化上限 +%d': 'Enhancement cap +%d reached',
    '缺少 +%d → +%d 的强化成本配置': 'Enhancement cost missing for +%d -> +%d',
    '学园币不足（需 %d）': 'Not enough School Coins (need %d)',
    '装备零件不足（需 %d）': 'Not enough Equipment Parts (need %d)',
    '未强化的装备无需重置（返还 0）': 'Unenhanced equipment does not need resetting (refund 0)',
    '章节纪念物不可分解': 'Chapter mementos cannot be dismantled', '（无）': '(none)',
})
out = ROOT / 'assets/localization/en.json'
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(f'{len(catalog)} reviewed translations -> {out}')
