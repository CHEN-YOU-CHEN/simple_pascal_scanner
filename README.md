# Pascal Scanner and Parser

這是一份使用 Lex (Flex) 與 Yacc (Bison) 實作的簡易 Pascal 語言詞法分析器 (Scanner) 與語法分析器 (Parser)。本程式可以對 Pascal 程式碼進行初步的語法判斷，並找出其中的錯誤內容。

## 專案環境與版本限制

本專案於 VirtualBox 虛擬機運行的 Ubuntu Linux 環境下開發與測試。
- **Flex 版本**: 2.6.4
- **Bison 版本**: (GNU Bison) 3.5.1
- **編譯器**: gcc (Ubuntu 9.4.0-1ubuntu1~20.04.2) 9.4.0

## 執行方式

請使用終端機進行編譯以及測試：

1. **編譯出執行檔**：
   ```bash
   make all
   ```
2. **執行並進行測試**：
   ```bash
   ./calc < filename.pas
   ```
3. **清除編譯產生的檔案**：
   ```bash
   make clean
   ```

## 實作重點與錯誤處理機制

本解析器特別針對以下幾種常見錯誤實作了偵測與恢復機制：

### 1. 未宣告變數
建立符號表。當解析到變數宣告階段時，會呼叫 `declare_temp_ids($3)` 將變數名稱與對應的型態（整數=1, 實數=2, 陣列=3, 字串=4）存入 `symtable` 中。當解析到變數被使用時，會查詢 `symtable`。若找不到該變數會回傳 -1，程式會立刻印出 `Line X: '變數名' is not defined`，同時將屬性 `$$ = -1` 往上傳遞，標記這是一個無效變數，並設定 `has_error = 1`。

### 2. 結構缺失
根據 Bison 內建的錯誤偵測及定義函式 `yyerror()`，當缺少特定關鍵字（例如 `if` 的後方缺少 `then`），Bison 會觸發 syntax error，由 `yyerror()` 印出錯誤訊息。

### 3. 型態不匹配 (Type Mismatch)
利用 Yacc 的 `%union` 定義了 `type_val`。每個變數（`varid`）或常數（`INT_NUM`, `STRING_LITERAL` 等）在被解析時，都會把自己的型態代碼賦值給 `$$`。
在 `simpexp`（例如加減法）與 `assign`（賦值）規則中，會去檢查左右兩邊子節點的型態（例如 `$1` 和 `$3`）。若發現 `$1 != $3` 就會呼叫 `type_name()` 函數將代碼轉回字串，並印出如 `Type mismatch: cannot add integer and string` 的錯誤，抓到型態不同的問題。

### 4. 缺少符號或使用錯誤符號
除了由 Bison 抓出符號遺漏之外，我們將容易混淆的符號在文法中加入特別規則。例如：為了處理錯誤地將 `:=` 寫成 `=`，在文法中加入了 `assign_eq: '='`。當配對到錯誤符號時，程式會主動報錯並進行錯誤恢復，以確保解析器能繼續執行。另外，若程式結尾缺少 `.`，也已在 `prog` 中加入對應的規則來捕捉並提示 `end of input found`。

### 5. 錯誤恢復 (Error Recovery)
在 `stmt_list` 與 `dec_list` 等核心列表規則中，加入了 `| error stmt_sep` 的機制。當發生語法錯誤時，Parser 會自動丟棄無法辨識的 token，直到遇到同步符號（例如分號 `;`），並重置錯誤狀態 (`has_error = 0; yyerrok;`)，繼續正確解析下一行程式碼。
