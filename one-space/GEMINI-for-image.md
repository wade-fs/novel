# 小說插圖生成規則 (Token 最佳化版)

## 1. 執行與省 Token 鐵律
- **批次優先**：當需要生成超過 2 張圖片時，禁止在對話中逐張呼叫生圖工具，必須撰寫並執行單一 Python 腳本呼叫 Gemini API 批次產圖，以消除多輪對話的 Context 重複計費。
- **極簡回覆**：禁止輸出思考過程、賞析或客套話。任務完成後，僅以條列式回報「檔案名稱：對應小節標題」即可。
- **Prompt 精煉**：每張圖的英文生圖 Prompt 嚴格控制在 60 個英文單字以內。

## 2. 統一視覺與角色錨點 (Consistency Anchors)
所有圖片必須套用以下基礎畫風與角色設定，無需回頭翻找原文細節：
- **統一畫風**：Eastern Xianxia fantasy digital painting, cinematic lighting, intricate traditional Chinese architecture, high detail, 16:9 aspect ratio.
- **顧淵 (Gu Yuan)**：Handsome young Taoist master, calm deep eyes, long black hair tied with a simple wooden hairpin, wearing a spotless moon-white scholar robe (月白長袍).
- **靈素 (Ling Su)**：Ethereal translucent spirit maiden, cold aloof beauty, snow-white skin, waist-length black hair, wearing ancient flowing aqua-white wide-sleeved feather robes (天水廣袖羽衣), faint starry aura.
- **柳清虛 (Liu Qingxu)**：Aloof pure fairy maiden, pale porcelain skin, slightly disheveled black hair, wearing a worn clean moon-white Taoist robe (月白道袍), carrying an ancient jade-hilted sword "Qiushui".

## 3. 預設生圖參數
- 預設模型：`gemini-3.1-flash-image`（不要使用 `gemini-3-pro-image`，pro 應該搭配解析度 2K）
- 解析度：`1K` （嚴禁設為 2K 或 4K，以維持單張 1,120 tokens 的最低標準消耗）
- 比例：`16:9`
