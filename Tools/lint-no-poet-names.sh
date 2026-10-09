#!/usr/bin/env bash
# CI 守线: 诗人内核与 UI 不得出现诗人专属【逻辑】或产品名。
#   从 zhi/poetkit/lint-no-poet-names.sh 移植 (PoetKit 并入 ZixiaoKit, 2026-10-01), 路径改为本仓库:
#   - 目标: 文件或目录 (目录则递归检查全部 .swift), 默认 ZixiaoPoet 与 ZixiaoPoetCore;
#   - 称谓: 诗人志系列的编成 (`../zhi/poetkit/compositions/*.json`, 可用 POET_COMPOSITIONS_DIR 覆盖) 里的
#     名 / slug / 字 / 号, 加上一份固定的产品与诗人名单 (编成目录不在时也能查)。
#   查的是代码, 不是注释 —— 注释里举例无妨, 写进 if 分支才是腐烂。
#   (架构师审核时另用 grep 查注释: `grep -rn "苏轼\|東坡\|..." Sources/ZixiaoPoet` 也应为零。)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-$ROOT/Sources/ZixiaoPoet}"
CORE_TARGET=""
if [[ $# -eq 0 ]]; then CORE_TARGET="$ROOT/Sources/ZixiaoPoetCore"; fi
COMPOSITIONS="${POET_COMPOSITIONS_DIR:-$ROOT/../zhi/poetkit/compositions}"

python3 - "$TARGET" "$COMPOSITIONS" "$CORE_TARGET" <<'PY'
import json, glob, re, sys, os
target, comp_dir = sys.argv[1], sys.argv[2]

# 固定名单: 已立项的产品与诗人 (产品 slug / bundle 末段 / 题名), 与架构师 grep 的名单一致。
names = {"苏轼", "東坡", "东坡", "李白", "杜甫", "suzi", "dongpozhi", "libai", "dufu", "sushi"}
comp_files = sorted(glob.glob(os.path.join(comp_dir, '*.json')))
for f in comp_files:
    p = json.load(open(f, encoding='utf-8'))['poet']
    names |= {p['name'], p['slug']} | {p[k] for k in ('style', 'hao') if p.get(k)}
names = {n for n in names if n}

files = [target] if os.path.isfile(target) else sorted(
    glob.glob(os.path.join(target, '**', '*.swift'), recursive=True))
if sys.argv[3]:
    files += sorted(glob.glob(os.path.join(sys.argv[3], '**', '*.swift'), recursive=True))

hits = []
for path in files:
    src = open(path, encoding='utf-8').read()
    # 剥掉块注释与行注释, 只留代码; 保留行号
    src = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group().count('\n'), src, flags=re.S)
    code = [re.sub(r'//.*$', '', ln) for ln in src.split('\n')]
    hits += [(path, i + 1, ln.strip(), n)
             for i, ln in enumerate(code) for n in sorted(names) if n in ln]

if hits:
    print("✗ 内核出现诗人专属逻辑 —— 该判断属于编成 / App 资源, 请移出 ZixiaoPoet:")
    for path, ln, txt, n in hits:
        print(f"    {os.path.relpath(path)}:{ln}  「{n}」  {txt[:80]}")
    sys.exit(1)
print(f"✓ 内核干净: {len(files)} 个文件 / {len(comp_files)} 份编成 / {len(names)} 个称谓, 无一出现在代码里 (注释不计)")
PY
