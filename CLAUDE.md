# iStore 產品查找工具（moriochang/model）

iStore 中區內部使用的 Apple 產品查詢與庫存工具。單一 `index.html`，部署在 GitHub Pages（push 到 `main` 即上線）。
使用者是 Morio（中區區經理），一律用**繁體中文**溝通與撰寫註解。

> 這個 repo 是**公開**的。不要把任何機密、員工 email 名單、營運腳本放進來。
> 營運腳本與金鑰在本機另一個資料夾（見「相關資料夾」）。

## 檔案

| 檔案 | 說明 |
|---|---|
| `index.html` | 整個網站（HTML + CSS + JS，約 6,400 行），刻意維持單一檔案 |
| `data.csv` | 產品主檔（約 1,500 筆），靜態部署 |
| `hotmodel_reference.csv` | Hotmodel 主打機型 SKU 清單，靜態部署 |
| `images/` | CARE 保險等頁面圖片 |
| `tools/check.sh` | 上傳前檢查，**每次改完 index.html 都要跑** |
| `.gitignore` | 擋掉金鑰、`.env`、`inventory.json` |

**庫存不在 repo 裡。** `inventory.json` 已改由 Supabase 提供，絕對不要再加回 repo 或改回 `fetch('inventory.json')`。

## 架構

```
瀏覽器 ── GitHub Pages：index.html / data.csv / hotmodel_reference.csv（公開、無機敏資料）
       ├─ Firebase Auth（專案 istore-login-tc）：Google 登入，限 @istore.com.tw
       │    token 內含 custom claims：app_role、can_view_overview
       └─ Supabase（專案 ziiwtzqwytrfaikzkmsj，東京，免費方案）
            public.get_inventory()  ← 前端唯一讀取入口，需 Firebase token + app_role
            private.inventory_snapshot（單筆，每次上傳覆蓋）
            private.inventory_access_log（稽核記錄）
            public.admin_upsert_inventory(p_data) ← 只授權 service_role，給上傳腳本用
            public.get_arrival() / admin_upsert_arrival()  ← 一週到貨，同樣模式（private.arrival_snapshot）
```

- Supabase 用 Third-Party Auth 信任 Firebase token，不另建帳號。
- 前端只放 **publishable key**（`sb_publishable_...`，設計上可公開）。**secret key（`sb_secret_...`）絕不能出現在 repo。**
- 前端的權限判斷只控制畫面顯示，**真正的防線在 `get_inventory()`**。
- 不做單店資料過濾：Hotmodel 轉貨建議、補貨分析需要全通路庫存。

## 權限

- 角色來源只有一個：Firebase custom claims（`app_role`），由本機 `set_firebase_claims.js` 設定。
- `index.html` 的 `ROLE_CAPABILITIES` 只定義「角色能做什麼」，**不放 email 名單**。
- 角色：`administrator`、`manager`、`store_75`、`store_77`。單店角色鎖定自己店（`canSwitchStore: false`），但仍讀全通路庫存。
- 庫存總覽頁：administrator 或 claim `can_view_overview: true`。
- 新增角色要改兩處：本機 `set_firebase_claims.js` 的名單 + `index.html` 的 `ROLE_CAPABILITIES`（Supabase 用 `store\_%` 比對，通常不用改）。
- 登入時一律 `getIdTokenResult(true)` 強制刷新，角色變更重新整理就生效。

## index.html 結構

行號會變動，用名稱搜尋。

| 區塊 | 內容 |
|---|---|
| `<style>` | 全站 CSS（含教育價樣式） |
| script 1（module） | Firebase 登入、`onAuthStateChanged`、登出 |
| script 2（module） | Supabase client（`window.supabaseClient`），以 Firebase ID token 當 accessToken |
| script 3（一般） | 主程式：產品搜尋、篩選、四個庫存頁、Hotmodel |
| script 4（一般，IIFE） | 教育價資料 `EDU_PRICE_DATA` 與頁面，與主程式隔離 |
| script 5（一般，IIFE） | 一週到貨頁：`initializeArrival()`（`rpc('get_arrival')`），讀主程式的 `inventoryData`、`originalData`、`columnMapping` |

主要名稱：

- 頁面切換：`showPage()`、`pageMap`、`.nav-btn[data-page]`
- 庫存：`loadInventory()`（呼叫 `rpc('get_inventory')`）、`inventoryData`、`storeInfo`、`inventoryLastUpdate`
- **`whenInventoryReady(fn)`**：庫存頁（lowstock / hotmodel / overview / hotmodelMatrix）只初始化一次，**必須等庫存載入後才畫**，否則會畫出空表且不會重畫。新增任何依賴庫存的頁面都要用它包起來
- Hotmodel：`HOT_MODEL_PRESETS`、`loadHotmodelReference()`、`buildHotmodelMatrix()`、`renderHotmodelMatrix()`、`measureLabelWidth()`
- 常數：`HOTMODEL_EXCLUDED_STORES = ['825','830']`（特賣會、維修中心不列入掃描與轉貨來源）、`FOCUS_REGION_STORES`（中區 75/76/77/81/84，矩陣表框線標示）
- 解析：`extractStorageCapacity()`、`extractWatchSize()`、`classifyCareDevice()`
- 一週到貨：導覽列最右邊，所有有庫存權限的角色都可見、可切換任一門市。第一次點才載入，庫存欄位用 `whenInventoryReady` 等庫存。
  型號（Apple Part #）用 `data.csv` 的 `manufacture_style` 對到品名與料號；對不到的是 CTO 客製機，品名後加灰色型號、庫存顯示「—」。
  樣式全部限定在 `#arrivalPage` 底下，並抵銷全站 `th`/`td`/`tbody tr` 樣式；浮動說明框 `.arr-pop` 掛在 `body`（`.container` 有 backdrop-filter，fixed 會跑位）
- `formatDataUpdateTime()`：沒有庫存時間時會退回顯示「現在時間」，看到資料時間等於當下時間，通常代表庫存沒載到

## Hotmodel 機型清單

`HOT_MODEL_PRESETS` 每一款用 `subcat`（對應 CSV 的「中分類」）＋ `kw`（`product_name` 包含的字串）比對 `hotmodel_reference.csv`。

- 以「款式」為單位：同款所有 SKU（顏色、錶帶）加總，全部為 0 才算缺貨。
- `hotmodel_reference.csv` 更新時，要同步檢查清單：每個 SKU 恰好被一款涵蓋，不能漏、不能重複。`tools/check.sh` 會檢查。
- 注意品名格式差異：iPhone 18 Pro 寫 `256`（無 G），iPhone 17 寫 `256G`，MBN 寫 `256GB`。`kw` 前後加空白（如 `' 256 '`、`' 42 '`）避免誤比對。

## 配色（使用者已確認，非要求不要改）

- 頁面背景、登入頁：勃根地紅 `#8b2440 → #4a1424`（iPhone 18 Pro 主打色）
- 標題列、彈窗標題、低庫存表頭：黑灰 `#1c1c1e → #48484a`（介面框架）
- 可點的動作、選中狀態（低庫存按鈕、分類標籤、登入 logo）：酒紅 `#a02c4e → #5c1a2b`、`#8b2440`
- 狀態色不動：缺貨紅、低庫存黃、正常綠、中區靛藍框線、Google 按鈕四色
- 其餘元件仍是原本藍色系。使用者曾否決整頁換成酒紅單色系（太單調）。

## 工作方式（使用者偏好）

- **只改被要求的部分**，不順手重構或改配色。修改範圍越小越好，完成後說明改了哪幾處。
- **開始任何修改前先 `git pull`**，使用者偶爾會直接在 GitHub 網頁上改（例如上傳新的 `hotmodel_reference.csv`）。
- 改完一定跑 `tools/check.sh`，有 UI 改動時用瀏覽器實際看過再交付。
- 解釋用繁體中文、白話，先講結論；不要用程式術語堆砌。
- 不要動 `SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY` 兩行。

## 檢查與測試

```bash
tools/check.sh            # 靜態檢查 + 各段 JS 語法 + Hotmodel 涵蓋率
```

本機預覽：`python3 -m http.server 8000` 後開 `http://localhost:8000`。
Firebase 授權網域要有 `localhost`，否則登入會被擋；`file://` 直接開也無法登入。

自動化測試（Playwright）時可以不登入：攔掉 Firebase/Supabase 外部模組，
用 `add_init_script` 注入假的 `window.supabaseClient = { rpc: () => Promise.resolve({ data, error: null }) }`，
再手動設 `hasInventoryPermission = true` 並呼叫 `initializeInventoryUI()`、`loadDefaultCSV()`、`loadInventory()`。
主程式用 `let` 宣告的全域變數可在 `page.evaluate` 直接存取。

## 部署

commit 並 push 到 `main`，GitHub Pages 約 1 分鐘生效，使用者需 `⌘ + Shift + R` 強制重新整理。
commit 前看一次 `git status`，確認沒有 `serviceAccountKey.json`、`.env`、`inventory.json`、`node_modules/`。

## 營運資料夾與電腦分工

所有東西都在 **Mac mini**（使用者從 MacBook Air 用 SSH 連進來操作）：

```
~/Claude_Projects/
├─ model/              本 repo：網站（公開，會 push 到 GitHub）
└─ istore_supabase/    營運：金鑰、權限名單、庫存轉檔與上傳（不進 git，有自己的 CLAUDE.md）
```

- 開 Claude 時用 `claude --add-dir ../istore_supabase`，才能同時看到兩邊。只改網站時可以不加。
- **`istore_supabase` 的任何東西都不能複製、移動或 commit 進本 repo**，包括金鑰、員工 email、內部網路位址。
- 每日庫存：使用者在 MacBook Air 從公司系統下載 XLS、點 Automator，Automator 透過 SSH 把檔案傳到 Mac mini 並執行 `istore_supabase/daily.sh` 轉檔上傳。細節見營運資料夾的 `CLAUDE.md`。
- 新增角色類型時兩邊都要改：本 repo 的 `ROLE_CAPABILITIES` ＋ `istore_supabase/set_firebase_claims.js`。
- `inventory.json` 的結構由 `istore_supabase/convert_inventory.py` 產生，前端依賴它；改結構時兩邊要同步。
- 測試需要真實庫存時，直接讀 `../istore_supabase/inventory.json`，**不要複製進 repo**。
