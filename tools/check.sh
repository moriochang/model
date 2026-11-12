#!/bin/bash
# ============================================================
# index.html 上傳前檢查
#   1. 必要設定還在、不該出現的東西沒出現
#   2. 每一段 <script> 的 JavaScript 語法
#   3. HOT_MODEL_PRESETS 是否完整涵蓋 hotmodel_reference.csv
#
# 用法：tools/check.sh [index.html 路徑]
# 需要：python3、node
# ============================================================

cd "$(dirname "$0")/.." || exit 1
TARGET="${1:-index.html}"
CSV="hotmodel_reference.csv"

if [ ! -f "$TARGET" ]; then echo "❌ 找不到 $TARGET"; exit 1; fi

PASS=0; FAIL=0
ok()   { echo "✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "❌ $1"; FAIL=$((FAIL+1)); }

must()    { grep -q -- "$1" "$TARGET" && ok "$2" || bad "$2 ← 缺少"; }
mustnot() { if grep -q -- "$1" "$TARGET"; then bad "$2 ← 不該出現"; grep -n -- "$1" "$TARGET" | head -3 | sed 's/^/      /'; else ok "$2"; fi; }

echo "🔍 檢查 $TARGET"
echo "── 必須存在 ──"
must "ziiwtzqwytrfaikzkmsj.supabase.co"  "Supabase 網址"
must "sb_publishable_"                   "Supabase publishable key"
must "rpc('get_inventory')"              "庫存經 Supabase RPC 讀取"
must "ROLE_CAPABILITIES"                 "角色能力表"
must "getIdTokenResult(true)"            "登入時強制刷新權限"
must "function whenInventoryReady"       "庫存頁等待載入機制"
must "showInventoryError"                "庫存錯誤提示"
must "rpc('get_arrival')"               "一週到貨經 Supabase RPC 讀取"
must "data-page=\"arrival\""              "一週到貨按鈕"

echo "── 不該存在 ──"
mustnot "YOUR-PROJECT-REF"         "佔位網址"
mustnot "fetch('inventory.json"    "靜態 inventory.json 讀取"
mustnot "USER_PERMISSIONS"         "舊版 email 權限表"
mustnot "OVERVIEW_ALLOWED_EMAILS"  "舊版 email 白名單"
mustnot "sb_secret_"               "secret key（嚴重）"

N=$(grep -c "@istore.com.tw'" "$TARGET")
[ "$N" -le 2 ] && ok "沒有 email 名單" || bad "發現 $N 處 email 字串，確認不是名單復活"

echo "── JavaScript 語法 ──"
TMP=$(mktemp -d)
python3 - "$TARGET" "$TMP" << 'PY'
import re, sys
html = open(sys.argv[1], encoding='utf-8').read()
for i, (attrs, body) in enumerate(re.findall(r'<script([^>]*)>(.*?)</script>', html, re.S)):
    if 'src=' in attrs: continue
    kind = 'module' if 'module' in attrs else 'classic'
    open(f'{sys.argv[2]}/{i:02d}_{kind}.js', 'w', encoding='utf-8').write(body)
PY
for f in "$TMP"/*.js; do
  name=$(basename "$f" .js)
  if [[ "$name" == *module ]]; then out=$(node --input-type=module --check < "$f" 2>&1)
  else out=$(node --check "$f" 2>&1); fi
  [ $? -eq 0 ] && ok "script $name" || { bad "script $name 語法錯誤"; echo "$out" | head -5 | sed 's/^/      /'; }
done
rm -rf "$TMP"

echo "── Hotmodel 機型涵蓋 ──"
if [ -f "$CSV" ]; then
  RES=$(python3 - "$TARGET" "$CSV" << 'PY'
import csv, re, sys
src = open(sys.argv[1], encoding='utf-8').read()
start = src.find('const HOT_MODEL_PRESETS = [')
if start < 0: print('FAIL 找不到 HOT_MODEL_PRESETS'); sys.exit()
block = src[start:src.index('];', start)]
presets = re.findall(r"label: '([^']+)', subcat: '([^']+)', kw: '([^']*)'", block)
rows = list(csv.DictReader(open(sys.argv[2], encoding='utf-8-sig')))
hits = {r['Code']: [] for r in rows}
empty = []
for label, subcat, kw in presets:
    m = [r for r in rows if r['中分類'] == subcat and kw in r['product_name']]
    if not m: empty.append(label)
    for r in m: hits[r['Code']].append(label)
miss = [c for c, v in hits.items() if not v]
dup  = [c for c, v in hits.items() if len(v) > 1]
print(f'INFO {len(presets)} 款機型，CSV {len(rows)} 筆 SKU')
for l in empty: print(f'FAIL 機型「{l}」對不到任何 SKU')
for c in miss: print(f'FAIL SKU {c} 沒有被任何機型涵蓋')
for c in dup:  print(f'FAIL SKU {c} 被重複計算：{"、".join(hits[c])}')
if not (empty or miss or dup): print('OK 每個 SKU 恰好被一款涵蓋')
PY
)
  while IFS= read -r line; do
    case "$line" in
      OK*)   ok "${line#OK }" ;;
      FAIL*) bad "${line#FAIL }" ;;
      INFO*) echo "   ${line#INFO }" ;;
    esac
  done <<< "$RES"
else
  echo "   （找不到 $CSV，略過）"
fi

echo "===================================================="
if [ "$FAIL" -eq 0 ]; then echo "🎉 全部通過（$PASS 項），可以上傳"; exit 0
else echo "⚠️  $FAIL 項需要處理，$PASS 項通過"; exit 1; fi
