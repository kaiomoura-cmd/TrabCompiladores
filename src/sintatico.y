%{
#include <iostream>
#include <string>
#include <vector>
#include <cstring>

#include "simbolos.h"
#include "temporarios.h"

int yylex();
void yyerror(const char *s);

struct Atributo {
    char* nome;
    int tipo;
};

TabelaDeSimbolos tabela;
GeradorDeTemporarios gerador;
DeclaracaoDeMemoria declarador;
std::vector<std::string> buffer_codigo;

Atributo gera_codigo_operacao(char* n1, int t1, const char* op, char* n2, int t2);
void gera_codigo_atribuicao(char* id, char* n_exp);
Atributo gera_codigo_casting(int tipo_destino, char* n_exp);

char* copia_string(const std::string& str) {
    char* cstr = new char[str.length() + 1];
    std::strcpy(cstr, str.c_str());
    return cstr;
}
%}

%union {
    char* str;
    struct {
        char* nome;
        int tipo;
    } info;
}

%token <str> ID NUM_INTEIRO NUM_REAL LITERAL_CHAR
%token T_INT T_FLOAT T_BOOL T_CHAR ';'
%token SOM SUB MULT DIV ATRIB ABRE_PAR FECHA_PAR
%token MAIOR MENOR MAIOR_IGUAL MENOR_IGUAL IGUAL DIFERENTE E_LOGICO OU_LOGICO NEGACAO

/* Ordem de Precedência  */
%left OU_LOGICO
%left E_LOGICO
%left IGUAL DIFERENTE
%left MAIOR MENOR MAIOR_IGUAL MENOR_IGUAL
%left SOM SUB
%left MULT DIV
%right NEGACAO
%left ABRE_PAR FECHA_PAR

%type <info> expressao

%%

programa: 
    | programa comando
    ;

comando: 
    T_INT ID ';' { tabela.inserir(std::string($2), Tipo::INT); }
    | T_FLOAT ID ';' { tabela.inserir(std::string($2), Tipo::FLOAT); }
    | T_BOOL ID ';' { tabela.inserir(std::string($2), Tipo::BOOL); }
    | T_CHAR ID ';' { tabela.inserir(std::string($2), Tipo::CHAR); }
    | ID ATRIB expressao ';' { gera_codigo_atribuicao($1, $3.nome); }
    | expressao ';' 
    ;

expressao: 
    NUM_INTEIRO { 
        std::string t = gerador.novoTemporario();
        $$.nome = copia_string(t); $$.tipo = 0;
        buffer_codigo.push_back("$" + t + " = " + std::string($1) + ";$");
    }
    | NUM_REAL { 
        std::string t = gerador.novoTemporario();
        $$.nome = copia_string(t); $$.tipo = 1;
        buffer_codigo.push_back("$" + t + " = " + std::string($1) + ";$");
    }
    | LITERAL_CHAR { 
        std::string t = gerador.novoTemporario();
        $$.nome = copia_string(t); $$.tipo = 3; 
        buffer_codigo.push_back("$" + t + " = " + std::string($1) + ";$");
    }
    | ID { 
        $$.nome = copia_string(std::string($1));
        std::string nome_str($1);
        if (tabela.existe(nome_str)) {
            $$.tipo = (tabela.buscar(nome_str) == Tipo::INT) ? 0 : 1;
        } else {
            $$.tipo = 0; 
        }
    }
    
    /* Operações Matemáticas */
    | expressao SOM expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "+", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; }
    | expressao SUB expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "-", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; }
    | expressao MULT expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "*", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; }
    | expressao DIV expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "/", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; }
    
    /* Operações Relacionais e Lógicas */
    | expressao MAIOR expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, ">", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 0; }
    | expressao MENOR expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "<", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 0; }
    | expressao MAIOR_IGUAL expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, ">=", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 0; }
    | expressao MENOR_IGUAL expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "<=", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 0; }
    | expressao IGUAL expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "==", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 0; }
    | expressao DIFERENTE expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "!=", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 0; }
    | expressao E_LOGICO expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "&&", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 0; }
    | expressao OU_LOGICO expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "||", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 0; }
    
    /* Negação Lógica (Operador Unário) */
    | NEGACAO expressao {
        std::string t_res = gerador.novoTemporario();
        $$.nome = copia_string(t_res);
        $$.tipo = 0; // Resultado de ! é sempre booleano/int
        buffer_codigo.push_back("$" + t_res + " = !" + std::string($2.nome) + ";$");
    }
    
    /* Casting e Parênteses */
    | ABRE_PAR T_INT FECHA_PAR expressao   { Atributo res = gera_codigo_casting(0, $4.nome); $$.nome = res.nome; $$.tipo = res.tipo; }
    | ABRE_PAR T_FLOAT FECHA_PAR expressao { Atributo res = gera_codigo_casting(1, $4.nome); $$.nome = res.nome; $$.tipo = res.tipo; }
    | ABRE_PAR expressao FECHA_PAR       { $$.nome = $2.nome; $$.tipo = $2.tipo; }
    ;

%%

Atributo gera_codigo_operacao(char* n1, int t1, const char* op, char* n2, int t2) {
    Atributo res;
    std::string t_res = gerador.novoTemporario();
    res.nome = copia_string(t_res);
    
    if (t1 == 0 && t2 == 1) {
        std::string t_conv = gerador.novoTemporario();
        buffer_codigo.push_back("$" + t_conv + " = (float) " + std::string(n1) + ";$");
        buffer_codigo.push_back("$" + t_res + " = " + t_conv + " " + op + " " + std::string(n2) + ";$");
        res.tipo = 1;
    } 
    else if (t1 == 1 && t2 == 0) {
        std::string t_conv = gerador.novoTemporario();
        buffer_codigo.push_back("$" + t_conv + " = (float) " + std::string(n2) + ";$");
        buffer_codigo.push_back("$" + t_res + " = " + std::string(n1) + " " + op + " " + t_conv + ";$");
        res.tipo = 1;
    } 
    else {
        buffer_codigo.push_back("$" + t_res + " = " + std::string(n1) + " " + op + " " + std::string(n2) + ";$");
        res.tipo = t1;
    }
    return res;
}

void gera_codigo_atribuicao(char* id, char* n_exp) {
    buffer_codigo.push_back("$" + std::string(id) + " = " + std::string(n_exp) + ";$");
}

Atributo gera_codigo_casting(int tipo_destino, char* n_exp) {
    Atributo res;
    std::string t_res = gerador.novoTemporario();
    res.nome = copia_string(t_res);
    res.tipo = tipo_destino;
    std::string str_tipo = (tipo_destino == 0) ? "int" : "float";
    
    buffer_codigo.push_back("$" + t_res + " = (" + str_tipo + ") " + std::string(n_exp) + ";$");
    return res;
}

void yyerror(const char *s) {
    std::cerr << "Erro Sintatico: " << s << std::endl;
}

int main() {
    yyparse();
    
    declarador.imprimirDeclaracoes(gerador.getTemporarios(), tabela, Tipo::INT);
    
    size_t i = 0;
    while (i < buffer_codigo.size()) {
        std::cout << buffer_codigo[i] << std::endl;
        i++;
    }
    
    return 0;
}