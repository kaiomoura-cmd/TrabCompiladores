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
%token TRUE FALSE

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
    | ID ATRIB expressao ';' { 
            std::string nome_str($1);

            // 1. Checa se a variável de destino existe na Tabela de Símbolos
            if (!tabela.existe(nome_str)) {
                std::string msg = "Erro Semantico: Variavel nao declarada: " + nome_str;
                yyerror(msg.c_str());
                exit(1);
            }

            // 2. Descobre o tipo numérico interno da variável que vai receber o valor
            Tipo tipo_real = tabela.buscar(nome_str);
            int tipo_destino = -1;
            
            if (tipo_real == Tipo::INT) tipo_destino = 0;
            else if (tipo_real == Tipo::FLOAT) tipo_destino = 1;
            else if (tipo_real == Tipo::BOOL) tipo_destino = 2;
            else if (tipo_real == Tipo::CHAR) tipo_destino = 3;

            // 3. Aplica a Filosofia Java/C# (Tipagem Forte)
            if (tipo_destino == $3.tipo) {
                // Regra A: Tipos idênticos (ex: int recebe int). Atribuição direta!
                gera_codigo_atribuicao($1, $3.nome);
            } 
            else if (tipo_destino == 1 && $3.tipo == 0) {
                // Regra B: Coerção Segura (Widening). Guardando um 'int' em um espaço 'float'.
                std::string t_conv = gerador.novoTemporario();
                buffer_codigo.push_back("$" + t_conv + " = (float) " + std::string($3.nome) + ";$");
                
                // Atribui o temporário que foi convertido para float à variável de destino
                gera_codigo_atribuicao($1, copia_string(t_conv));
            } 
            else {
                // Regra C: Mistura proibida! (ex: float em int, char em bool, etc).
                std::string msg = "Erro Semantico: Tipos incompativeis na atribuicao para a variavel '" + nome_str + "'.";
                yyerror(msg.c_str());
                exit(1);
            }
        }
    | expressao ';' 
    | bloco
    ;

bloco:
      '{' { tabela.entrarEscopo(); } comandos_bloco '}' { tabela.sairEscopo(); }
    ;

comandos_bloco:
      /* Vazio (permite blocos sem nada dentro tipo { }) */
    | comandos_bloco comando
    ;

expressao: 
    NUM_INTEIRO { 
        $$.nome = copia_string(std::string($1));
        $$.tipo = 0; // INT
    }
    | NUM_REAL { 
        $$.nome = copia_string(std::string($1));
        $$.tipo = 1; // FLOAT
    }
    | LITERAL_CHAR { 
        $$.nome = copia_string(std::string($1));
        $$.tipo = 3; // CHAR
    }
    | TRUE { // Token para a palavra true
        $$.nome = copia_string("1");
        $$.tipo = 2; // BOOL
    }
    | FALSE { // Token para a palavra false
        $$.nome = copia_string("0");
        $$.tipo = 2; // BOOL
    }
    | ID { 
        $$.nome = copia_string(std::string($1));
        std::string nome_str($1);
        
        // 1. Verifica se a variável realmente existe na tabela
        if (tabela.existe(nome_str)) {
            
            // 2. Busca o tipo real da variável
            Tipo tipo_real = tabela.buscar(nome_str);
            
            // 3. Mapeia o Enum (Tipo) para o código inteiro usado no parser
            if (tipo_real == Tipo::INT) {
                $$.tipo = 0;
            } else if (tipo_real == Tipo::FLOAT) {
                $$.tipo = 1;
            } else if (tipo_real == Tipo::BOOL) {
                $$.tipo = 2;
            } else if (tipo_real == Tipo::CHAR) {
                $$.tipo = 3;
            }
            
        } else {
            // 4. Se não existe, aborta a compilação com Erro Semântico
            std::string msg = "Erro Semantico: Variavel nao declarada: " + nome_str;
            yyerror(msg.c_str());
            exit(1); 
        }
    }
    
    /* Operações Matemáticas */
    | expressao SOM expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "+", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; }
    | expressao SUB expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "-", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; }
    | expressao MULT expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "*", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; }
    | expressao DIV expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "/", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; }
    
    /* Operações Relacionais (>, <, >=, <=, ==, !=) */
    | expressao MAIOR expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, ">", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; }
    | expressao MENOR expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "<", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; }
    | expressao MAIOR_IGUAL expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, ">=", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; }
    | expressao MENOR_IGUAL expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "<=", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; }
    | expressao IGUAL expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "==", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; }
    | expressao DIFERENTE expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "!=", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; }
    
    /* Operações Lógicas (&&, ||) */
    | expressao E_LOGICO expressao { 
        if ($1.tipo != 2 || $3.tipo != 2) {
            yyerror("Erro Semantico: Operador '&&' exige tipos booleanos.");
            exit(1);
        }
        Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "&&", $3.nome, $3.tipo); 
        $$.nome = res.nome; 
        $$.tipo = 2; // Retorna BOOL
    }
    | expressao OU_LOGICO expressao { 
        if ($1.tipo != 2 || $3.tipo != 2) {
            yyerror("Erro Semantico: Operador '||' exige tipos booleanos.");
            exit(1);
        }
        Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "||", $3.nome, $3.tipo); 
        $$.nome = res.nome; 
        $$.tipo = 2; // Retorna BOOL
    }
    
    /* Negação Lógica (Operador Unário !) */
    | NEGACAO expressao {
        if ($2.tipo != 2) {
            yyerror("Erro Semantico: Operador '!' exige um tipo booleano.");
            exit(1);
        }
        std::string t_res = gerador.novoTemporario();
        $$.nome = copia_string(t_res);
        $$.tipo = 2; // Resultado de ! é sempre booleano
        buffer_codigo.push_back("$" + t_res + " = !" + std::string($2.nome) + ";$");
    }
    
    /* Menos Unário (Números Negativos) */
    | SUB expressao %prec NEGACAO {
        if ($2.tipo != 0 && $2.tipo != 1) {
            yyerror("Erro Semantico: O operador unario '-' exige um tipo numerico (int ou float).");
            exit(1);
        }
        
        std::string t_res = gerador.novoTemporario();
        $$.nome = copia_string(t_res);
        $$.tipo = $2.tipo; // Mantém o tipo (se era int, continua int. se era float, continua float)
        
        buffer_codigo.push_back("$" + t_res + " = -" + std::string($2.nome) + ";$");
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
    
    // REGRA 1: Se os tipos são idênticos, a operação segue normalmente (ex: int + int)
    if (t1 == t2) {
        buffer_codigo.push_back("$" + t_res + " = " + std::string(n1) + " " + op + " " + std::string(n2) + ";$");
        res.tipo = t1;
    } 
    // REGRA 2: Coerção Segura (Widening) -> int (0) + float (1)
    else if (t1 == 0 && t2 == 1) {
        std::string t_conv = gerador.novoTemporario();
        buffer_codigo.push_back("$" + t_conv + " = (float) " + std::string(n1) + ";$");
        buffer_codigo.push_back("$" + t_res + " = " + t_conv + " " + op + " " + std::string(n2) + ";$");
        res.tipo = 1; // O resultado vira float
    } 
    // REGRA 3: Coerção Segura (Widening) -> float (1) + int (0)
    else if (t1 == 1 && t2 == 0) {
        std::string t_conv = gerador.novoTemporario();
        buffer_codigo.push_back("$" + t_conv + " = (float) " + std::string(n2) + ";$");
        buffer_codigo.push_back("$" + t_res + " = " + std::string(n1) + " " + op + " " + t_conv + ";$");
        res.tipo = 1; // O resultado vira float
    } 
    // REGRA 4: Filosofia Java/C# -> Qualquer outra mistura é proibida!
    else {
        // Lança o Erro Semântico e aborta a compilação para não gerar código sujo
        std::string msg = "Erro Semantico: Tipos incompativeis para a operacao '" + std::string(op) + "'.";
        yyerror(msg.c_str());
        exit(1); 
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
    std::cerr << s << std::endl;
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