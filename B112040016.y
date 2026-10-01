%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// 宣告全域變數，用於紀錄目前掃描到第幾行、第幾個字元。讓 yyerror() 能夠印出錯誤訊息
extern int yylex();
extern int lineCount;
extern int charCount;
extern unsigned tokenStartChar;
extern char line_buf[1024];

void yyerror(const char *s);

// 宣告 symboltable 的資料型態，內容包含變數名稱及型態
typedef struct {
    char *name;
    int type;
} Symbol;

Symbol symtable[200];
int symCount = 0;

// 當程式碼使用到 id 時會呼叫此函數來確認該變數是否存在 symboltable
int lookup_symbol(const char *name) 
{
    for (int i = 0; i < symCount; i++) 
    {
        if (strcmp(symtable[i].name, name) == 0) 
        {
            return i;
        }
    }
    return -1;
}

// 當要將加入變數加入 symbol table前要先確認是否重複宣告 
void add_symbol(const char *name, int type) 
{
    if (lookup_symbol(name) == -1) 
    {
        symtable[symCount].name = strdup(name);
        symtable[symCount].type = type;
        symCount++;
    }
}

// 在讀入變數名稱時還不知道資料的型態，先將變數名加入 temp_list，等到讀到型態再一起加入symbol table
char* temp_id_list[100];
int temp_id_count = 0;

void add_temp_id(const char* name) 
{
    temp_id_list[temp_id_count++] = strdup(name);
}

// 為了將成功加入 symbol table 的名稱刪除或避免錯誤的宣告導致 temp_list 存到錯誤的變數名稱，此函式用於清空 temp_list 
void clear_temp_ids() 
{
    for(int i = 0; i < temp_id_count; i++) 
    {
        free(temp_id_list[i]);
    }
    temp_id_count = 0;
}

// 將目前存入暫存區的變數名稱，已指定的型態加入 symbol table
void declare_temp_ids(int type) 
{
    for (int i = 0; i < temp_id_count; i++) 
    {
        add_symbol(temp_id_list[i], type);
    }
    clear_temp_ids();
}

// 當檢查到錯誤文法時將此變數設為 1
int has_error = 0;

// 定義各型態 1=int, 2=real, 3=array, 4=string
const char* type_name(int t) {
    if (t == 1) return "integer";
    if (t == 2) return "real";
    if (t == 3) return "array";
    if (t == 4) return "string";
    return "unknown";
}

%}

/* Definition Section */

/* token 或 non-terminal 可能有不同資料，定義 Bison 內部 semantic stack 中變數 yylval 的資料型態結構。允許不同種類的記號在 stack 中存放各自需要的資料型態。 */
%union {
    int int_val;
    double real_val;
    char *str_val;
    int type_val;
}

/* 宣告 keyword 及 operator 這些不需要額外攜帶資料的token，只需要回傳用於輸出錯誤訊息的代號 */
%token PROGRAM "program"
%token VAR "var"
%token BEGIN_SYM "begin"
%token END_SYM "end"
%token ARRAY "array"
%token OF "of"
%token INTEGER_SYM "integer"
%token REALTYPE_SYM "real"
%token READ "read"
%token WRITE "write"
%token FOR "for"
%token DO "do"
%token TO "to"
%token IF "if"
%token THEN "then"
%token ELSE "else"
%token DIV_SYM "div"
%token MOD_SYM "mod"
%token WRITELN "writeln"
%token STRING_TYPE_SYM "string"
%token ASSIGN_SYM ":="
%token NEQ_SYM "<>"
%token LEQ_SYM "<="
%token GEQ_SYM ">="
%token DOT_DOT ".."

/* 宣告攜帶資料的 token，根據不同資料型態的宣告將資料填入 %union 的對應欄位中 */
%token <str_val> ID "identifier"                  /* 識別碼 (如變數名、程式名)，攜帶字串指標 */
%token <str_val> STRING_LITERAL "string literal"  /* 字串字面值 (如 'aa')，攜帶字串內容 */
%token <int_val> INT_NUM "integer number"         /* 整數常數 (如 5, 10)，攜帶整數值 */
%token <real_val> REAL_NUM "real number"          /* 實數常數 (如 3.14)，攜帶雙精度浮點數值 */

%type <type_val> standtype type simpexp term factor exp varid

%define parse.error verbose

%left '+' '-' 					/* 加法與減法：左結合，優先權較低 */
%left '*' DIV_SYM MOD_SYM			/* 乘法與除法/餘數：左結合，優先權較高 */
%nonassoc '=' '<' '>' NEQ_SYM LEQ_SYM GEQ_SYM	/* 關係運算子：無結合律，禁止連續比較 */

/* 為處理 else 的歧義問題，讓 ELSE 比 LOWER_THAN_ELSE 更高的優先權，讓else 和距離最近的 if一組。 */
%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE

%%
/* grammar rule section */

/* 定義 Pascal 程式的最外層架構：program 程式名 var 變數宣告區 程式碼主體 . 並加入了 `| error '.'` 的錯誤恢復機制*/
prog:
    PROGRAM prog_name ';' VAR dec_list ';' body '.'
    | error '.' { yyerrok; }
    ;

prog_name:
    ID
    ;

/* 允許連續多行的變數宣告，並以分號 ';' 隔開 */
dec_list:
    dec
    | dec_list ';' dec
    ;


dec:
    id_list ':' type { declare_temp_ids($3); }
    | id_list error type { yyerrok; declare_temp_ids($3); }
    ;

/* 型態定義 (type / standtype / arraytype)，解析完成後將型態代碼 (1=int, 2=real, 3=array, 4=string) 存入 $$ 往上傳遞 */
type:
    standtype { $$ = $1; }
    | arraytype { $$ = 3; }
    ;

standtype:
    INTEGER_SYM    { $$ = 1; }
    | REALTYPE_SYM { $$ = 2; }
    | STRING_TYPE_SYM { $$ = 4; }
    ;

arraytype:
    ARRAY '[' INT_NUM DOT_DOT INT_NUM ']' OF standtype
    ;

/* 變數名稱串列 (id_list)。允許 i, j, k 這種連續宣告，先將名稱存入temp_id_list 中等待註冊 */
id_list:
    ID { add_temp_id($1); }
    | id_list ',' ID { add_temp_id($3); }
    ;

/* stmt_list 程式主體內部的執行語句集合。實作 Panic Mode，當敘述發生錯誤，忽略錯誤的 Token 直到遇見分號，並宣告 yyerrok 並將 has_error 歸零，使 Parser 繼續解析下一行 */
stmt_list:
    stmt
    | stmt_list ';' stmt
    | error ';' { yyerrok; has_error = 0; }
    | stmt_list ';' error ';' { yyerrok; has_error = 0; }
    ;

stmt:
    assign
    | read
    | write
    | writeln_stmt
    | for
    | ifstmt
    ;

/* 用來抓出將賦值符號 ':=' 錯打成 '=' 的情況。主動印出預期錯誤 */
assign_eq:
    '=' {
        printf("Line %d, at char %d, := expected but = found\n", lineCount, tokenStartChar);
        has_error = 1;
    }
    ;

/* 包含合法的 ASSIGN_SYM 以及上述攔截的 assign_eq。即使發生 '=' 的語法錯誤，Parser 仍會繼續解析右邊的 simpexp ($3)，並且檢查左邊變數 ($1) 與右邊算式 ($3) 的型態是否一致。不一致則印出 Type Mismatch */
assign:
    varid ASSIGN_SYM simpexp {
        if ($1 != -1 && $3 != -1 && $1 != $3 && $1 != 3) {
            printf("Line %d: Type mismatch in assignment: cannot assign %s to %s variable\n",
                   lineCount, type_name($3), type_name($1));
            has_error = 1;
        }
    }
    | varid assign_eq simpexp {
        if ($1 != -1 && $3 != -1 && $1 != $3 && $1 != 3) {
            printf("Line %d: Type mismatch in assignment: cannot assign %s to %s variable\n",
                   lineCount, type_name($3), type_name($1));
            has_error = 1;
        }
    }
    ;

/* 使用 %prec LOWER_THAN_ELSE 強迫 else 綁定給最近的 if */
ifstmt:
    IF '(' exp ')' THEN stmt %prec LOWER_THAN_ELSE
    | IF '(' exp ')' THEN stmt ELSE stmt
    | IF '(' exp ')' THEN body %prec LOWER_THAN_ELSE
    | IF '(' exp ')' THEN body ELSE body
    ;

exp:
    simpexp { $$ = $1; }
    | exp relop simpexp { $$ = 1; }
    ;

relop:
    '>' | '<' | GEQ_SYM | LEQ_SYM | NEQ_SYM | '='
    ;

/* 算術運算與型態檢查，由下而上取得左右兩側的型態 ($1 與 $3)，若型態不相同且皆為合法變數，則印出 Type Mismatch 錯誤，並將左側型態 $$ = $1 繼續往上傳遞 */
simpexp:
    term { $$ = $1; }
    | simpexp '+' term { 
        if ($1 != -1 && $3 != -1 && $1 != $3) {
            printf("Line %d: Type mismatch: cannot add %s and %s\n",
                   lineCount, type_name($1), type_name($3));
            has_error = 1;
        }
        $$ = $1; 
    }
    | simpexp '-' term {
        if ($1 != -1 && $3 != -1 && $1 != $3) {
            printf("Line %d: Type mismatch: cannot subtract %s and %s\n",
                   lineCount, type_name($1), type_name($3));
            has_error = 1;
        }
        $$ = $1;
    }
    ;

term:
    factor { $$ = $1; }
    | term '*' factor {
        if ($1 != -1 && $3 != -1 && $1 != $3) {
            printf("Line %d: Type mismatch: cannot multiply %s and %s\n",
                   lineCount, type_name($1), type_name($3));
            has_error = 1;
        }
        $$ = $1;
    }
    | term DIV_SYM factor { $$ = $1; }
    | term MOD_SYM factor { $$ = $1; }
    ;

/* 將常數直接轉換為對應的型態代碼 (整數=1, 實數=2, 字串=4) 往上傳遞 */
factor:
    varid { $$ = $1; }
    | INT_NUM { $$ = 1; }
    | REAL_NUM { $$ = 2; }
    | STRING_LITERAL { $$ = 4; }
    | '+' factor { $$ = $2; }
    | '-' factor { $$ = $2; }
    | '(' simpexp ')' { $$ = $2; }
    ;

/* I/O 與迴圈操作 (read, write, for) */
read:
    READ '(' id_list_use ')'
    ;

write:
    WRITE '(' write_list ')'
    ;

writeln_stmt:
    WRITELN
    | WRITELN '(' write_list ')'
    ;

write_list:
    write_item
    | write_list ',' write_item
    ;

write_item:
    exp
    ;

/* 變數使用檢查，當在程式主體中使用變數時，呼叫 lookup_symbol() 查詢符號表。若回傳 -1，代表變數未經宣告，立刻印出 'x' is not defined 的錯誤，並將 $$ 設為 -1 往上傳遞，告知上層節點此變數無效，不需再做型態檢查 */
id_list_use:
    ID { 
        if (lookup_symbol($1) == -1) {
            printf("Line %d: '%s' is not defined\n", lineCount, $1);
            has_error = 1;
        }
    }
    | id_list_use ',' ID {
        if (lookup_symbol($3) == -1) {
            printf("Line %d: '%s' is not defined\n", lineCount, $3);
            has_error = 1;
        }
    }
    ;

for:
    FOR index_exp DO stmt
    | FOR index_exp DO body
    ;

index_exp:
    varid ASSIGN_SYM simpexp TO exp
    ;

varid:
    ID { 
        int idx = lookup_symbol($1);
        if (idx == -1) {
            printf("Line %d: '%s' is not defined\n", lineCount, $1); 
            $$ = -1; 
            has_error = 1;
        } else {
            $$ = symtable[idx].type;
        }
    }
    | ID '[' simpexp ']' {
        int idx = lookup_symbol($1);
        if (idx == -1) {
            printf("Line %d: '%s' is not defined\n", lineCount, $1);
            $$ = -1;
            has_error = 1;
        } else {
            $$ = 1;
        }
    }
    ;

/* 程式區塊，處理 begin ... end 的結構。加入 error 恢復機制，若 begin 到 end 中間發生語法錯誤，尋找 end 作為同步點安全結束 */
body:
    BEGIN_SYM stmt_list END_SYM
    | BEGIN_SYM stmt_list ';' END_SYM
    | BEGIN_SYM error END_SYM { yyerrok; has_error = 0; }
    | BEGIN_SYM stmt_list ';' error END_SYM { yyerrok; has_error = 0; }
    ;

%%


void yyerror(const char *s) 
{
    // / 若發生語法錯誤，將全域標記設為 1，告知 Lexer 不要印這行損壞的原始碼
    has_error = 1;
    
    // 使用靜態變數記錄上一次發生錯誤的行號與字元位置
    static int last_error_line = -1;
    static int last_error_char = -1;

    // 
    if (lineCount == last_error_line && tokenStartChar == last_error_char) 
    {
        return; 
    }
    
    
    const char *unex = strstr(s, "unexpected ");
    const char *expct = strstr(s, "expecting ");
    
    // 如果有找到這兩個關鍵字，代表成功攔截到了詳細報錯字串
    if (unex && expct)
    {
        char found_tok[64] = "", exp_tok[64] = "";

	// 將指標向後推移，跳過 "unexpected " (長度 11) 與 "expecting " (長度 10) 前綴，讓指標直接對準真正的錯誤符號字串開頭
        unex += 11;
        expct += 10;
        
	// 字元複製進 found_tok，直到遇到逗號 (Bison 預設用逗號分隔) 或是到達陣列上限。
        int i = 0;
        while (unex[i] && unex[i] != ',' && i < 63) 
        { 
            found_tok[i] = unex[i]; 
            i++; 
        }
        found_tok[i] = '\0';
        
	// 字元複製進 exp_tok。特別處理 " or "：如果 Bison 吐出 "expecting X or Y"，在讀到空白加 "or" 時就停止確保只拿第一個預期符號，以符合規格書格式。
        i = 0;
        while (expct[i] && expct[i] != ',' && i < 63) 
	{ 
            if (expct[i] == ' ' && expct[i+1] == 'o' && expct[i+2] == 'r') 
	    {
                break; 
            }
            exp_tok[i] = expct[i]; 
            i++; 
        }
        exp_tok[i] = '\0';
     
	// Bison 吐出來的 expected 字串，通常是我們在 %token 宣告的巨集變數名稱。需要利用 strcmp 比對，將這些大寫的內部變數改回規格書要求的格式。
        if (strcmp(exp_tok, "ASSIGN_SYM") == 0) strcpy(exp_tok, ":=");
        if (strcmp(exp_tok, "':'") == 0) strcpy(exp_tok, ":");
        if (strcmp(exp_tok, "';'") == 0) strcpy(exp_tok, ";");
        if (strcmp(exp_tok, "THEN") == 0) strcpy(exp_tok, "then");
        if (strcmp(exp_tok, "BEGIN_SYM") == 0) strcpy(exp_tok, "begin");
        if (strcmp(exp_tok, "END_SYM") == 0) strcpy(exp_tok, "end");
        if (strcmp(exp_tok, "'.'") == 0) strcpy(exp_tok, ".");
        
        // 處理 Bison 用 "$end" 來表示檔案結束 (EOF)，將其翻譯為 "end"
        if (strcmp(found_tok, "$end") == 0 || strcmp(found_tok, "end of file") == 0) strcpy(found_tok, "end");
               
        if (found_tok[0] == '\'' && found_tok[strlen(found_tok)-1] == '\'') 
	{
            memmove(found_tok, found_tok+1, strlen(found_tok));
            found_tok[strlen(found_tok)-1] = '\0';
        }

	// 將底層的 ID 變數名統一翻譯為規格書要求的 "identifier"
        if (strcmp(found_tok, "ID") == 0 || strcmp(found_tok, "identifier") == 0) strcpy(found_tok, "identifier");
	
	// 如果預期是 begin 但抓到 =，此錯誤會破壞前面的 assign_eq，因此直接 return 交由 Yacc 的內部錯誤恢復機制處理。
        if (strcmp(exp_tok, "begin") == 0 && strcmp(found_tok, "=") == 0) 
	{
            return; 
        }

	// 依照規格書要求的精準格式印出「行號、字元位置、預期符號、實際符號」
        printf("Line %d, at char %d, %s expected but %s found\n", 
               lineCount, tokenStartChar, exp_tok, found_tok);
        
	// 更新靜態變數
        last_error_line = lineCount;
        last_error_char = tokenStartChar;
    } 
    else 
    {
	// 若無 unexpected/expecting，就直接印出 Bison 傳來的 s 字串
        printf("Line %d, at char %d, %s\n", lineCount, tokenStartChar, s);
        last_error_line = lineCount;
        last_error_char = tokenStartChar;
    }
}

int main(void) 
{
    // 呼叫 yyparse() 啟動 Yacc 的狀態機，開始進行整份檔案的語法解析
    yyparse();

    // 當 yyparse() 掃描到 EOF 後，line_buf裡可能還殘留最後一行的字串。如果這一行沒有發生錯誤，需要把它印出來。
    if (strlen(line_buf) > 0 && !has_error) 
    {
        int only_ws = 1;

	// 檢查該行是否只是一堆純空白或 Tab。若是純空白行，就不印出
        for (int i = 0; line_buf[i]; i++) 
   	{
            if (line_buf[i] != ' ' && line_buf[i] != '\t') { only_ws = 0; break; }
        }
        if (!only_ws)
            printf("Line %d: %s\n", lineCount, line_buf);
    }
    return 0;
}