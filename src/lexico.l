%option noyywrap

%{
#include "sintatico.tab.h"
#include <string.h>
#include <stdlib.h>

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
"read"                 { return READ; }
"write"                { return WRITE; }
"true"                 { yylval.str = copia_string_lex("1"); return TRUE; }
"false"                { yylval.str = copia_string_lex("0"); return FALSE; }
\'[a-zA-Z0-9]\'        { yylval.str = copia_string_lex(yytext); return LITERAL_CHAR; }
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

"+"                    { return SOM; }
"-"                    { return SUB; }
"*"                    { return MULT; }
"/"                    { return DIV; }
"="                    { return ATRIB; }
"("                    { return ABRE_PAR; }
")"                    { return FECHA_PAR; }
"{"                    { return '{'; }
"}"                    { return '}'; }
";"                    { return ';'; }

[ \t\n\r]+             {}
.                      { return yytext[0]; }

%%