%option caseless
%option noyywrap

%{
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "y.tab.h"

// 記錄目前的行號與字元位置
unsigned charCount = 1, lineCount = 1;

// 記錄目前掃描到的 token 的起始位置，用於報錯時精準指出錯誤在哪個字元
unsigned tokenStartChar = 1;

// 記錄上一個 token 的結束位置，用於 EOF 報錯
unsigned lastTokenLine = 1;
unsigned lastTokenChar = 1;

// 用來暫存每一行的完整程式碼內容，等到換行時再印出
char line_buf[1024] = "";
extern int has_error;

// 定義巨集：每次抓到新 token 時，將它的起始字元位置記錄下來
// 同時記錄該 token 的結束位置，給 EOF 使用
#define TOKEN_START() do { \
    tokenStartChar = charCount; \
    lastTokenLine = lineCount; \
    lastTokenChar = charCount + yyleng; \
} while(0)

// 將剛剛掃描到的字串附加到暫存區 (line_buf) 的尾端
void append_buf(const char* s) {
    strcat(line_buf, s);
}

// 處理換行：當遇到換行符號時，如果這一行沒有發生錯誤且不是空白行，就印出完整的這行程式碼
void process_newline() {
    if (strlen(line_buf) > 0 && !has_error) {
        int only_ws = 1;
        for (int i = 0; line_buf[i]; i++) {
            if (line_buf[i] != ' ' && line_buf[i] != '\t') { only_ws = 0; break; }
        }
        if (!only_ws)
            printf("Line %d: %s\n", lineCount, line_buf);
    }
    // 清空暫存區，行號加一，字元計數歸一，並將錯誤標記重置
    line_buf[0] = '\0';
    lineCount++;
    charCount = 1;
    has_error = 0;
}

%}

/* definition section */
space     [ ]
eol       (\r\n|\n)
tab       [\t]
 /* 匹配 (* 註解 *) 的格式 */
comment   \(\*([^*]|\*+[^*)])*\*+\)   
 /* 變數名稱 (Identifier) */  
id        [a-zA-Z_][a-zA-Z0-9_]*        
digit     [0-9]
 /* 實數，支援科學記號 */
real      {digit}+\.{digit}+([eE][+-]?{digit}+)?  
 /* 整數 */
integer   {digit}+         
 /* 字串，允許兩個單引號表示跳脫 */             
string    '([^']|'')*'                 
 /* 一般符號 */
symbol    [\(\)\+\-\*\/\.\;\:\,\=\[\]<>] 

%%

 /* rule section */

{space} {
    charCount++;
    append_buf(yytext);
}

{eol} {
    process_newline();
}

{tab} {
    charCount += 8;
    append_buf(yytext);
}

 /* 處理註解，不回傳 token，遇到換行就印出，遇到一般字元就增加字元計數 */
{comment} {
    int i;
    for(i=0; i<yyleng; i++) 
    {
        if(yytext[i] == '\n') 
    	{
            process_newline();
        } 
	else if(yytext[i] != '\r') 
	{
            charCount++;
        }
    }
}

 /* 關鍵字 (Keywords)：更新字元位置、存入緩衝區、並回傳對應的 Token 給 Bison */
"program" { TOKEN_START(); charCount += yyleng; append_buf(yytext); return PROGRAM; }
"var"     { TOKEN_START(); charCount += yyleng; append_buf(yytext); return VAR; }
"begin"   { TOKEN_START(); charCount += yyleng; append_buf(yytext); return BEGIN_SYM; }
"end"     { TOKEN_START(); charCount += yyleng; append_buf(yytext); return END_SYM; }
"array"   { TOKEN_START(); charCount += yyleng; append_buf(yytext); return ARRAY; }
"of"      { TOKEN_START(); charCount += yyleng; append_buf(yytext); return OF; }
"integer" { TOKEN_START(); charCount += yyleng; append_buf(yytext); return INTEGER_SYM; }
"real"    { TOKEN_START(); charCount += yyleng; append_buf(yytext); return REALTYPE_SYM; }
"read"    { TOKEN_START(); charCount += yyleng; append_buf(yytext); return READ; }
"write"   { TOKEN_START(); charCount += yyleng; append_buf(yytext); return WRITE; }
"for"     { TOKEN_START(); charCount += yyleng; append_buf(yytext); return FOR; }
"do"      { TOKEN_START(); charCount += yyleng; append_buf(yytext); return DO; }
"to"      { TOKEN_START(); charCount += yyleng; append_buf(yytext); return TO; }
"if"      { TOKEN_START(); charCount += yyleng; append_buf(yytext); return IF; }
"then"    { TOKEN_START(); charCount += yyleng; append_buf(yytext); return THEN; }
"else"    { TOKEN_START(); charCount += yyleng; append_buf(yytext); return ELSE; }
"div"     { TOKEN_START(); charCount += yyleng; append_buf(yytext); return DIV_SYM; }
"mod"     { TOKEN_START(); charCount += yyleng; append_buf(yytext); return MOD_SYM; }
"writeln" { TOKEN_START(); charCount += yyleng; append_buf(yytext); return WRITELN; }
"string"  { TOKEN_START(); charCount += yyleng; append_buf(yytext); return STRING_TYPE_SYM; }

":="      { TOKEN_START(); charCount += yyleng; append_buf(yytext); return ASSIGN_SYM; }
"<>"      { TOKEN_START(); charCount += yyleng; append_buf(yytext); return NEQ_SYM; }
"<="      { TOKEN_START(); charCount += yyleng; append_buf(yytext); return LEQ_SYM; }
">="      { TOKEN_START(); charCount += yyleng; append_buf(yytext); return GEQ_SYM; }
".."      { TOKEN_START(); charCount += yyleng; append_buf(yytext); return DOT_DOT; }

 /* 辨識變數名稱，並將其字串內容存入 yylval 中傳給 Bison */
{id} {
    TOKEN_START(); charCount += yyleng;
    append_buf(yytext);
    yylval.str_val = strdup(yytext);
    return ID;
}

 /* 辨識整數，透過 atoi 轉換數值並存入 yylval */
{integer} {
    TOKEN_START(); charCount += yyleng;
    append_buf(yytext);
    yylval.int_val = atoi(yytext);
    return INT_NUM;
}

{real} {
    TOKEN_START(); charCount += yyleng;
    append_buf(yytext);
    yylval.real_val = atof(yytext);
    return REAL_NUM;
}

{string} {
    TOKEN_START(); charCount += yyleng;
    append_buf(yytext);
    yylval.str_val = strdup(yytext);
    return STRING_LITERAL;
}

{symbol} {
    TOKEN_START(); charCount += yyleng;
    append_buf(yytext);
    return yytext[0];
}

. {
    TOKEN_START(); charCount++;
    append_buf(yytext);
    return yytext[0];
}

<<EOF>> {
    tokenStartChar = lastTokenChar;
    lineCount = lastTokenLine;
    return 0;
}

%%