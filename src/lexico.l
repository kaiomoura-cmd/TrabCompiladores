%option noyywrap
%option yylineno

%{
#include "sintatico.tab.h"
#include <string.h>
#include <stdlib.h>
#include <string>

void yyerror(const char *s);

char* copia_string_lex(const char* texto) {
    char* cstr = new char[strlen(texto) + 1];
    strcpy(cstr, texto);
    return cstr;
}
%}

%%

[0-9]+\.[0-9]+         { yylval.str = copia_string_lex(yytext); return NUM_REAL; }
[0-9]+                 { yylval.str = copia_string_lex(yytext); return NUM_INTEIRO; }
"int"                  { return T_INT; }
"float"                { return T_FLOAT; }
"bool"                 { return T_BOOL; }
"char"                 { return T_CHAR; }
"string"               { return T_STRING; }
"void"                 { return T_VOID; }
"return"               { return RETURN; }
"enum"                 { return ENUM; }
"read"                 { return READ; }
"write"                { return WRITE; }
"true"                 { yylval.str = copia_string_lex("1"); return TRUE; }
"false"                { yylval.str = copia_string_lex("0"); return FALSE; }
"if"                   { return IF; }
"else"                 { return ELSE; }
"while"                { return WHILE; }
"for"                  { return FOR; }
"switch"               { return SWITCH; }
"case"                 { return CASE; }
"default"              { return DEFAULT; }
"break"                { return BREAK; }
"continue"             { return CONTINUE; }
\'([^'\\\n]|\\.)\'     { yylval.str = copia_string_lex(yytext); return LITERAL_CHAR; }
\"([^\"\n\\]|\\.)*\"   {yylval.str = copia_string_lex(yytext); return LITERAL_STRING;}
[a-zA-Z_][a-zA-Z0-9_]* { yylval.str = copia_string_lex(yytext); return ID; }

">="                   { return MAIOR_IGUAL; }
"<="                   { return MENOR_IGUAL; }
"=="                   { return IGUAL; }
"!="                   { return DIFERENTE; }
">"                    { return MAIOR; }
"<"                    { return MENOR; }
"&&"                   { return E_LOGICO; }
"||"                   { return OU_LOGICO; }
"!"                    { return NEGACAO; }

"+="                   { return MAIS_ATRIB; }
"-="                   { return MENOS_ATRIB; }
"*="                   { return MULT_ATRIB; }
"/="                   { return DIV_ATRIB; }
"++"                   { return INC; }
"--"                   { return DEC; }

"+"                    { return SOM; }
"-"                    { return SUB; }
"*"                    { return MULT; }
"/"                    { return DIV; }
"="                    { return ATRIB; }
"("                    { return ABRE_PAR; }
")"                    { return FECHA_PAR; }
"{"                    { return '{'; }
"}"                    { return '}'; }
"["                    { return '['; }
"]"                    { return ']'; }
";"                    { return ';'; }
":"                    { return ':'; }
","                    { return ','; }

[ \t\n\r]+              {}
"/*"([^*]|\*+[^*/])*\*+"/" {}
"//"[^\n]*              {}
.                       {
                            std::string msg = "Caractere inválido: '";
                            msg += yytext[0];
                            msg += "'";
                            yyerror(msg.c_str());
                        }

%%