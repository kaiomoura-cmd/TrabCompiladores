%{
#include <iostream>
#include <string>
#include <vector>
#include <cstring>
#include <unordered_set>
#include <algorithm>

#include "simbolos.h"
#include "temporarios.h"

int yylex();
void yyerror(const char *s);
extern FILE* yyin; 
extern int yylineno; // Flex line counter

TabelaDeSimbolos tabela;
GeradorDeTemporarios gerador;
DeclaracaoDeMemoria declarador;

// Buffers do Main (Global)
std::vector<std::string> buffer_decls_global;
std::vector<std::string> buffer_codigo_global;

// Buffers de Função
std::vector<std::string> buffer_decls_funcao;
std::vector<std::string> buffer_codigo_funcao;

// Ponteiros de Buffer Dinâmicos (redirecionam codegen se dentro de função)
std::vector<std::string>* buffer_decls_atual = &buffer_decls_global;
std::vector<std::string>* buffer_atual = &buffer_codigo_global;

#define buffer_decls (*buffer_decls_atual)
#define buffer_codigo (*buffer_atual)

// Outros buffers globais
std::vector<std::string> buffer_funcoes_global;
std::vector<std::string> buffer_enums_global;

std::unordered_set<std::string> tabela_enums;
Tipo tipo_declaracao_atual;

bool dentro_de_funcao = false;
std::string nome_funcao_atual = "";
Tipo tipo_retorno_atual = Tipo::VOID;
std::string params_c_atual = "";

// ─── Gerador de Labels (L1, L2, L3, ...) ──────────────────────────────────
static int contador_labels = 0;
std::string novoLabel() {
    return "L" + std::to_string(++contador_labels);
}

// ─── Contador de profundidade de laço (para validar break/continue) ────────
static int nivel_laco = 0;

std::vector<std::string> pilha_labels_fim;   
std::vector<std::string> pilha_labels_ini;   
std::vector<std::string> pilha_laco_fim;   
std::vector<std::string> pilha_laco_ini;   

std::vector<std::string> buffer_incr_for;

char* copia_string(const std::string& str) {
    char* cstr = new char[str.length() + 1];
    std::strcpy(cstr, str.c_str());
    return cstr;
}
%}

%code requires {
#include <string>
#include <vector>
#include "simbolos.h"

struct Atributo {
    char* nome;
    int tipo;
};

struct Param {
    std::string nome;
    Tipo tipo;
};
}

%code {
// Declarações adicionais de funções auxiliares após a definição do YYSTYPE
Atributo gera_codigo_operacao(char* n1, int t1, const char* op, char* n2, int t2);
void gera_codigo_atribuicao(char* id, char* n_exp);
Atributo gera_codigo_casting(int tipo_destino, char* n_exp);
void faz_atribuicao(char* id, int tipo_destino, char* n_exp, int tipo_exp);
}

%union {
    char* str;
    Atributo info;
    int int_val;
    std::vector<Param>* param_list;
    std::vector<Atributo>* arg_list;
    std::vector<std::string>* str_list;
    std::vector<std::vector<Atributo>*>* matrix_list;
    Param* param_val;
}

%token <str> ID NUM_INTEIRO NUM_REAL LITERAL_CHAR LITERAL_STRING
%token T_INT T_FLOAT T_BOOL T_CHAR T_STRING
%token SOM SUB MULT DIV ATRIB ABRE_PAR FECHA_PAR
%token MAIOR MENOR MAIOR_IGUAL MENOR_IGUAL IGUAL DIFERENTE E_LOGICO OU_LOGICO NEGACAO
%token TRUE FALSE
%token READ WRITE
%token IF ELSE WHILE FOR SWITCH CASE DEFAULT BREAK CONTINUE
%token T_VOID RETURN ENUM
%token MAIS_ATRIB MENOS_ATRIB MULT_ATRIB DIV_ATRIB
%token INC DEC

/* Resolução do conflito clássico do dangling-else */
%nonassoc SEM_ELSE
%nonassoc ELSE

/* Ordem de Precedência  */
%left OU_LOGICO
%left E_LOGICO
%left IGUAL DIFERENTE
%left MAIOR MENOR MAIOR_IGUAL MENOR_IGUAL
%left SOM SUB
%left MULT DIV
%right NEGACAO INC DEC UNARY
%left ABRE_PAR FECHA_PAR '[' ']'

%type <info> expressao lvalue
%type <str>  label_if label_while_inicio label_for_inicio
%type <int_val> tipo
%type <param_list> parametros_op lista_parametros
%type <arg_list> argumentos_op lista_argumentos lista_valores
%type <str_list> lista_identificadores
%type <matrix_list> lista_linhas_matriz
%type <param_val> parametro

%%

programa: 
    | programa elemento
    ;

elemento:
      funcao
    | comando
    ;

comando:
    /* Declaracao de enums */
    ENUM ID '{' lista_identificadores '}' ';' {
        std::string enum_nome($2);
        tabela_enums.insert(enum_nome);
        std::vector<std::string>* ids = $4;
        std::string c_enum = "enum " + enum_nome + " { ";
        for (size_t i = 0; i < ids->size(); ++i) {
            std::string id_nome = (*ids)[i];
            Simbolo simb;
            simb.nome = id_nome;
            simb.tipo = Tipo::INT;
            simb.eh_enum_const = true;
            simb.valor_enum = (int)i;
            simb.nome_enum_tipo = enum_nome;
            tabela.inserirSimbolo(id_nome, simb);
            if (i > 0) c_enum += ", ";
            c_enum += id_nome;
        }
        c_enum += " };";
        buffer_enums_global.push_back(c_enum);
        delete ids;
    }
    /* Declaracao inline múltipla */
    | tipo lista_declaracoes ';'
    /* Declaracao de vetor (1D) simples */
    | tipo ID '[' NUM_INTEIRO ']' ';' {
        std::string nome_var($2);
        int dim = std::stoi($4);
        Tipo t = (Tipo)$1;
        Simbolo simb;
        simb.nome = nome_var;
        simb.tipo = t;
        simb.eh_vetor = true;
        simb.dim1 = dim;
        tabela.inserirSimbolo(nome_var, simb);
        buffer_decls.push_back(tipoParaString(t) + " " + nome_var + "[" + std::to_string(dim) + "];");
    }
    /* Declaracao de matriz (2D) simples */
    | tipo ID '[' NUM_INTEIRO ']' '[' NUM_INTEIRO ']' ';' {
        std::string nome_var($2);
        int dim1 = std::stoi($4);
        int dim2 = std::stoi($7);
        Tipo t = (Tipo)$1;
        Simbolo simb;
        simb.nome = nome_var;
        simb.tipo = t;
        simb.eh_matriz = true;
        simb.dim1 = dim1;
        simb.dim2 = dim2;
        tabela.inserirSimbolo(nome_var, simb);
        buffer_decls.push_back(tipoParaString(t) + " " + nome_var + "[" + std::to_string(dim1) + "][" + std::to_string(dim2) + "];");
    }
    /* Declaracao de vetor inicializado */
    | tipo ID '[' NUM_INTEIRO ']' ATRIB '{' lista_valores '}' ';' {
        std::string nome_var($2);
        int dim = std::stoi($4);
        Tipo t = (Tipo)$1;
        std::vector<Atributo>* vals = $8;
        if (vals->size() > (size_t)dim) {
            yyerror("Erro Semantico: Inicializadores excedem o tamanho do vetor.");
            exit(1);
        }
        std::string init_str = "";
        for (size_t i = 0; i < vals->size(); ++i) {
            if (i > 0) init_str += ", ";
            if (t != (Tipo)(*vals)[i].tipo) {
                yyerror("Erro Semantico: Inicializador com tipo incompativel.");
                exit(1);
            }
            init_str += (*vals)[i].nome;
        }
        Simbolo simb;
        simb.nome = nome_var;
        simb.tipo = t;
        simb.eh_vetor = true;
        simb.dim1 = dim;
        tabela.inserirSimbolo(nome_var, simb);
        buffer_decls.push_back(tipoParaString(t) + " " + nome_var + "[" + std::to_string(dim) + "] = {" + init_str + "};");
        delete vals;
    }
    /* Declaracao de matriz inicializada */
    | tipo ID '[' NUM_INTEIRO ']' '[' NUM_INTEIRO ']' ATRIB '{' lista_linhas_matriz '}' ';' {
        std::string nome_var($2);
        int dim1 = std::stoi($4);
        int dim2 = std::stoi($7);
        Tipo t = (Tipo)$1;
        std::vector<std::vector<Atributo>*>* linhas = $11;
        if (linhas->size() > (size_t)dim1) {
            yyerror("Erro Semantico: Numero de linhas maior que dim1.");
            exit(1);
        }
        std::string init_str = "";
        for (size_t r = 0; r < linhas->size(); ++r) {
            std::vector<Atributo>* cols = (*linhas)[r];
            if (cols->size() > (size_t)dim2) {
                yyerror("Erro Semantico: Numero de colunas maior que dim2.");
                exit(1);
            }
            if (r > 0) init_str += ", ";
            init_str += "{";
            for (size_t c = 0; c < cols->size(); ++c) {
                if (c > 0) init_str += ", ";
                if (t != (Tipo)(*cols)[c].tipo) {
                    yyerror("Erro Semantico: Tipo de valor invalido na inicializacao da matriz.");
                    exit(1);
                }
                init_str += (*cols)[c].nome;
            }
            init_str += "}";
            delete cols;
        }
        Simbolo simb;
        simb.nome = nome_var;
        simb.tipo = t;
        simb.eh_matriz = true;
        simb.dim1 = dim1;
        simb.dim2 = dim2;
        tabela.inserirSimbolo(nome_var, simb);
        buffer_decls.push_back(tipoParaString(t) + " " + nome_var + "[" + std::to_string(dim1) + "][" + std::to_string(dim2) + "] = {" + init_str + "};");
        delete linhas;
    }
    /* Atribuicao padrao */
    | lvalue ATRIB expressao ';' {
        std::string lval_nome($1.nome);
        int tipo_dest = $1.tipo;
        if (tipo_dest == $3.tipo) {
            if (tipo_dest == 4) {
                buffer_codigo.push_back("strcpy(" + lval_nome + ", " + std::string($3.nome) + ");");
            } else {
                buffer_codigo.push_back(lval_nome + " = " + std::string($3.nome) + ";");
            }
        } else if (tipo_dest == 1 && $3.tipo == 0) {
            std::string t_conv = gerador.novoTemporario();
            buffer_codigo.push_back(t_conv + " = (float) " + std::string($3.nome) + ";");
            buffer_codigo.push_back(lval_nome + " = " + t_conv + ";");
        } else {
            yyerror("Erro Semantico: Tipos incompativeis na atribuicao.");
            exit(1);
        }
    }
    /* Atribuicao de Slice */
    | lvalue ATRIB ID '[' expressao ':' expressao ']' ';' {
        std::string dest($1.nome);
        std::string src($3);
        if (!tabela.existe(src)) {
            yyerror("Erro Semantico: Vetor nao encontrado.");
            exit(1);
        }
        Simbolo simb_src = tabela.buscarSimbolo(src);
        if (!simb_src.eh_vetor) {
            yyerror("Erro Semantico: Slice exige vetor de origem.");
            exit(1);
        }
        std::string dest_var = dest;
        size_t brk = dest_var.find('[');
        if (brk != std::string::npos) dest_var = dest_var.substr(0, brk);
        Simbolo simb_dest = tabela.buscarSimbolo(dest_var);
        if (!simb_dest.eh_vetor) {
            yyerror("Erro Semantico: Atribuicao de slice exige vetor de destino.");
            exit(1);
        }
        if ($5.tipo != 0 || $7.tipo != 0) {
            yyerror("Erro Semantico: Indices do slice devem ser inteiros.");
            exit(1);
        }
        if (simb_src.tipo != simb_dest.tipo) {
            yyerror("Erro Semantico: Tipo do slice incompativel com o destino.");
            exit(1);
        }
        std::string t_sl = gerador.novoTemporario();
        std::string t_lim = gerador.novoTemporario();
        buffer_codigo.push_back(t_lim + " = " + std::string($7.nome) + " - " + std::string($5.nome) + ";");
        buffer_codigo.push_back("for (int " + t_sl + " = 0; " + t_sl + " < " + t_lim + "; " + t_sl + "++) {");
        buffer_codigo.push_back("    " + dest_var + "[" + t_sl + "] = " + src + "[" + std::string($5.nome) + " + " + t_sl + "];");
        buffer_codigo.push_back("}");
    }
    /* Operadores compostos */
    | lvalue MAIS_ATRIB expressao ';' {
        Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "+", $3.nome, $3.tipo);
        faz_atribuicao($1.nome, $1.tipo, res.nome, res.tipo);
    }
    | lvalue MENOS_ATRIB expressao ';' {
        Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "-", $3.nome, $3.tipo);
        faz_atribuicao($1.nome, $1.tipo, res.nome, res.tipo);
    }
    | lvalue MULT_ATRIB expressao ';' {
        Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "*", $3.nome, $3.tipo);
        faz_atribuicao($1.nome, $1.tipo, res.nome, res.tipo);
    }
    | lvalue DIV_ATRIB expressao ';' {
        Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "/", $3.nome, $3.tipo);
        faz_atribuicao($1.nome, $1.tipo, res.nome, res.tipo);
    }
    /* Unários como Instruções */
    | lvalue INC ';' {
        if ($1.tipo != 0 && $1.tipo != 1) {
            yyerror("Erro Semantico: Incremento invalido.");
            exit(1);
        }
        buffer_codigo.push_back(std::string($1.nome) + "++;");
    }
    | lvalue DEC ';' {
        if ($1.tipo != 0 && $1.tipo != 1) {
            yyerror("Erro Semantico: Decremento invalido.");
            exit(1);
        }
        buffer_codigo.push_back(std::string($1.nome) + "--;");
    }
    | INC lvalue ';' {
        if ($2.tipo != 0 && $2.tipo != 1) {
            yyerror("Erro Semantico: Incremento invalido.");
            exit(1);
        }
        buffer_codigo.push_back("++" + std::string($2.nome) + ";");
    }
    | DEC lvalue ';' {
        if ($2.tipo != 0 && $2.tipo != 1) {
            yyerror("Erro Semantico: Decremento invalido.");
            exit(1);
        }
        buffer_codigo.push_back("--" + std::string($2.nome) + ";");
    }
    /* Retorno de Funções */
    | RETURN expressao ';' {
        if (!dentro_de_funcao) {
            yyerror("Erro Semantico: 'return' fora de funcao.");
            exit(1);
        }
        if (tipo_retorno_atual == Tipo::VOID) {
            yyerror("Erro Semantico: Funcao void nao deve retornar valor.");
            exit(1);
        }
        if (tipo_retorno_atual == (Tipo)$2.tipo) {
            buffer_codigo.push_back("return " + std::string($2.nome) + ";");
        } else if (tipo_retorno_atual == Tipo::FLOAT && $2.tipo == 0) {
            std::string t_conv = gerador.novoTemporario();
            buffer_codigo.push_back(t_conv + " = (float) " + std::string($2.nome) + ";");
            buffer_codigo.push_back("return " + t_conv + ";");
        } else {
            yyerror("Erro Semantico: Tipo de retorno incompativel.");
            exit(1);
        }
    }
    | RETURN ';' {
        if (!dentro_de_funcao) {
            yyerror("Erro Semantico: 'return' fora de funcao.");
            exit(1);
        }
        if (tipo_retorno_atual != Tipo::VOID) {
            yyerror("Erro Semantico: Funcao nao-void deve retornar valor.");
            exit(1);
        }
        buffer_codigo.push_back("return;");
    }
    | READ ABRE_PAR lvalue FECHA_PAR ';' {
            std::string nome_str($3.nome);
            Tipo tipo_real = (Tipo)$3.tipo;
            std::string fmt = "%d";
            std::string extra_space = "";
            if (tipo_real == Tipo::FLOAT) {
                fmt = "%f";
            } else if (tipo_real == Tipo::CHAR) {
                fmt = "%c";
                extra_space = " ";
            } else if (tipo_real == Tipo::STRING) {
                fmt = "%s";
            }
            if (tipo_real == Tipo::STRING) {
                buffer_codigo.push_back("scanf(\"" + fmt + "\", " + nome_str + ");");
            } else {
                buffer_codigo.push_back("scanf(\"" + extra_space + fmt + "\", &" + nome_str + ");");
            }
        }
    | WRITE ABRE_PAR expressao FECHA_PAR ';' {
            std::string fmt = "%d\\n";
            if ($3.tipo == 1) {
                fmt = "%f\\n";
            } else if ($3.tipo == 3) {
                fmt = "%c\\n";
            } else if ($3.tipo == 4) {
                fmt = "%s\\n";
            }
            buffer_codigo.push_back("printf(\"" + fmt + "\", " + std::string($3.nome) + ");");
        }
    /* Escrita de Slices */
    | WRITE ABRE_PAR ID '[' expressao ':' expressao ']' FECHA_PAR ';' {
        std::string src($3);
        if (!tabela.existe(src)) {
            yyerror("Erro Semantico: Vetor nao encontrado.");
            exit(1);
        }
        Simbolo simb = tabela.buscarSimbolo(src);
        if (!simb.eh_vetor) {
            yyerror("Erro Semantico: Exige vetor.");
            exit(1);
        }
        if ($5.tipo != 0 || $7.tipo != 0) {
            yyerror("Erro Semantico: Indices do slice devem ser inteiros.");
            exit(1);
        }
        std::string t_sl = gerador.novoTemporario();
        std::string t_lim = gerador.novoTemporario();
        buffer_codigo.push_back(t_lim + " = " + std::string($7.nome) + " - " + std::string($5.nome) + ";");
        buffer_codigo.push_back("printf(\"[\");");
        buffer_codigo.push_back("for (int " + t_sl + " = 0; " + t_sl + " < " + t_lim + "; " + t_sl + "++) {");
        buffer_codigo.push_back("    if (" + t_sl + " > 0) printf(\", \");");
        if (simb.tipo == Tipo::INT) {
            buffer_codigo.push_back("    printf(\"%d\", " + src + "[" + std::string($5.nome) + " + " + t_sl + "]);");
        } else if (simb.tipo == Tipo::FLOAT) {
            buffer_codigo.push_back("    printf(\"%f\", " + src + "[" + std::string($5.nome) + " + " + t_sl + "]);");
        } else if (simb.tipo == Tipo::CHAR) {
            buffer_codigo.push_back("    printf(\"%c\", " + src + "[" + std::string($5.nome) + " + " + t_sl + "]);");
        }
        buffer_codigo.push_back("}");
        buffer_codigo.push_back("printf(\"]\\n\");");
    }
    | cmd_if
    | cmd_while
    | cmd_for
    | cmd_switch
    | BREAK ';' {
            if (nivel_laco == 0) {
                yyerror("Erro Semantico: 'break' usado fora de um laco ou switch.");
                exit(1);
            }
            /* Usa a pilha EXCLUSIVA de laços — ignora labels de if aninhados */
            buffer_codigo.push_back("goto " + pilha_laco_fim.back() + ";");
        }
    | CONTINUE ';' {
            if (nivel_laco == 0) {
                yyerror("Erro Semantico: 'continue' usado fora de um laco.");
                exit(1);
            }
            /* Usa a pilha EXCLUSIVA de laços — ignora labels de if aninhados */
            buffer_codigo.push_back("goto " + pilha_laco_ini.back() + ";");
        }
    | expressao ';' 
    | bloco
    ;

/* Regras de Escopo (Blocos de código) */
bloco:
      '{' { 
          tabela.entrarEscopo(); 
          buffer_codigo.push_back("{"); // Abre escopo no C
        } comandos_bloco '}' { 
          tabela.sairEscopo(); 
          buffer_codigo.push_back("}"); // Fecha escopo no C
        }
    ;

comandos_bloco:
      /* Vazio (O cenário base para o Bison saber parar) */
    | comandos_bloco comando
    ;

/* ══════════════════════════════════════════════════════════════════════════
   ESTRUTURAS DE CONTROLE DE FLUXO
   ══════════════════════════════════════════════════════════════════════════ */

/* ─── IF / ELSE ─────────────────────────────────────────────────────────── */
/*
   Estratégia de geração de código:

   if (cond) stmt                    if (cond) stmt else stmt_e
   ─────────────────────────         ──────────────────────────────────
   ifFalse <cond> goto L_fim         ifFalse <cond> goto L_else
   <stmt>                            <stmt>
   L_fim:                            goto L_fim
                                     L_else:
                                     <stmt_e>
                                     L_fim:
*/

/* Ação intermediária: gerada ANTES de analisar o corpo do if.
   Gera o salto condicional e empilha o label de fim. */
label_if:
    ABRE_PAR expressao FECHA_PAR {
        // ── Verificação Semântica: condição deve ser bool (tipo 2) ──
        if ($2.tipo != 2) {
            yyerror("Erro Semantico: A condicao do 'if' deve ser do tipo bool.");
            exit(1);
        }
        std::string l_senao = novoLabel();
        buffer_codigo.push_back("if (!(" + std::string($2.nome) + ")) goto " + l_senao + ";");
        pilha_labels_fim.push_back(l_senao); // Empilha para uso após o corpo
        $$ = copia_string(l_senao);
    }
    ;

cmd_if:
    IF label_if comando %prec SEM_ELSE {
        /* if sem else: coloca o label de fim logo após o corpo */
        std::string l_fim = pilha_labels_fim.back();
        pilha_labels_fim.pop_back();
        buffer_codigo.push_back(l_fim + ":");
    }
    | IF label_if comando ELSE {
        /* Antes de compilar o else:
           1. Gera o goto para pular o bloco else após executar o then
           2. Fecha o label onde o ifFalse saltou (início do else)
           3. Empilha o novo label de fim (após o else) */
        std::string l_else = pilha_labels_fim.back();
        pilha_labels_fim.pop_back();
        std::string l_fim = novoLabel();
        buffer_codigo.push_back("goto " + l_fim + ";");
        buffer_codigo.push_back(l_else + ":");
        pilha_labels_fim.push_back(l_fim); // Empilha label de fim do if-else
    } comando {
        /* Fecha o label de fim após o bloco else */
        std::string l_fim = pilha_labels_fim.back();
        pilha_labels_fim.pop_back();
        buffer_codigo.push_back(l_fim + ":");
    }
    ;

/* ─── WHILE ──────────────────────────────────────────────────────────────── */
/*
   Estratégia:
   L_inicio:
   ifFalse <cond> goto L_fim
   <corpo>
   goto L_inicio
   L_fim:
*/
label_while_inicio:
    /* Ação vazia que marca o início do laço ANTES de avaliar a condição */
    %empty {
        std::string l_ini = novoLabel();
        buffer_codigo.push_back(l_ini + ":");
        pilha_labels_ini.push_back(l_ini);
        $$ = copia_string(l_ini);
    }
    ;

cmd_while:
    WHILE label_while_inicio ABRE_PAR expressao FECHA_PAR {
        // ── Verificação Semântica: condição deve ser bool (tipo 2) ──
        if ($4.tipo != 2) {
            yyerror("Erro Semantico: A condicao do 'while' deve ser do tipo bool.");
            exit(1);
        }
        std::string l_fim = novoLabel();
        buffer_codigo.push_back("if (!(" + std::string($4.nome) + ")) goto " + l_fim + ";");
        // Empilha nas pilhas DE LAÇO (usadas por break/continue)
        pilha_laco_fim.push_back(l_fim);
        pilha_laco_ini.push_back(pilha_labels_ini.back());
        nivel_laco++;
    } comando {
        nivel_laco--;
        std::string l_fim = pilha_laco_fim.back(); pilha_laco_fim.pop_back();
        pilha_laco_ini.pop_back();
        std::string l_ini = pilha_labels_ini.back(); pilha_labels_ini.pop_back();
        buffer_codigo.push_back("goto " + l_ini + ";");
        buffer_codigo.push_back(l_fim + ":");
    }
    ;

/* ─── FOR ────────────────────────────────────────────────────────────────── */
/*
   Estratégia CORRETA do for:
   <init>
   L_inicio:       ← label de retorno da condição
   ifFalse <cond> goto L_fim
   <corpo>
   <incr>          ← incremento: compilado DEPOIS do corpo, antes do goto
   goto L_inicio
   L_fim:

   PROBLEMA: No Bison a gramática é:
     for ( init_for ; expressao ; incr_for ) comando
   O incr_for é parseado ANTES do corpo. Usamos buffer_incr_for
   para "guardar" o código do incremento e emiti-lo após o corpo.
*/

label_for_inicio:
    /* Ação vazia: marca o ponto de retorno da condição do for */
    %empty {
        std::string l_ini = novoLabel();
        buffer_codigo.push_back(l_ini + ":");
        pilha_labels_ini.push_back(l_ini);
        $$ = copia_string(l_ini);
    }
    ;

cmd_for:
    FOR ABRE_PAR init_for ';' label_for_inicio expressao ';' {
        // ── Verificação Semântica: condição deve ser bool (tipo 2) ──
        if ($6.tipo != 2) {
            yyerror("Erro Semantico: A condicao do 'for' deve ser do tipo bool.");
            exit(1);
        }
        std::string l_fim = novoLabel();
        buffer_codigo.push_back("if (!(" + std::string($6.nome) + ")) goto " + l_fim + ";");
        // Empilha nas pilhas DE LAÇO (usadas por break/continue)
        pilha_laco_fim.push_back(l_fim);
        pilha_laco_ini.push_back(pilha_labels_ini.back());
        // O incremento vai ser parseado agora mas emitido depois do corpo
        // Usamos um índice para saber onde o buffer de incr começa
        buffer_incr_for.clear();
    } incr_for FECHA_PAR {
        nivel_laco++;
    } comando {
        nivel_laco--;
        // Emite o incremento (que foi capturado separadamente) após o corpo
        for (const auto& linha : buffer_incr_for) {
            buffer_codigo.push_back(linha);
        }
        buffer_incr_for.clear();
        std::string l_fim = pilha_laco_fim.back(); pilha_laco_fim.pop_back();
        pilha_laco_ini.pop_back();
        std::string l_ini = pilha_labels_ini.back(); pilha_labels_ini.pop_back();
        buffer_codigo.push_back("goto " + l_ini + ";");
        buffer_codigo.push_back(l_fim + ":");
    }
    ;

init_for:
      /* Vazio — for (;cond;incr) */
    | ID ATRIB expressao {
        /* Variavel ja declarada, so atribui */
        std::string nome_str($1);
        if (!tabela.existe(nome_str)) {
            std::string msg = "Erro Semantico: Variavel nao declarada: " + nome_str;
            yyerror(msg.c_str());
            exit(1);
        }
        Tipo tipo_real = tabela.buscar(nome_str);
        int tipo_destino = -1;
        if (tipo_real == Tipo::INT)   tipo_destino = 0;
        else if (tipo_real == Tipo::FLOAT) tipo_destino = 1;
        else if (tipo_real == Tipo::BOOL)  tipo_destino = 2;
        else if (tipo_real == Tipo::CHAR)  tipo_destino = 3;
        faz_atribuicao($1, tipo_destino, $3.nome, $3.tipo);
    }
    /* Fix 2: for com declaracao inline — for(int i = 0; ...) */
    | T_INT ID ATRIB expressao {
        if ($4.tipo != 0) {
            yyerror("Erro Semantico: Tipo incompativel na declaracao int do 'for'.");
            exit(1);
        }
        tabela.inserir(std::string($2), Tipo::INT);
        buffer_decls.push_back("int " + std::string($2) + ";");
        buffer_codigo.push_back(std::string($2) + " = " + std::string($4.nome) + ";");
    }
    | T_FLOAT ID ATRIB expressao {
        tabela.inserir(std::string($2), Tipo::FLOAT);
        buffer_decls.push_back("float " + std::string($2) + ";");
        if ($4.tipo == 1) {
            buffer_codigo.push_back(std::string($2) + " = " + std::string($4.nome) + ";");
        } else if ($4.tipo == 0) {
            std::string t_conv = gerador.novoTemporario();
            buffer_codigo.push_back(t_conv + " = (float) " + std::string($4.nome) + ";");
            buffer_codigo.push_back(std::string($2) + " = " + t_conv + ";");
        } else {
            yyerror("Erro Semantico: Tipo incompativel na declaracao float do 'for'.");
            exit(1);
        }
    }
    | T_BOOL ID ATRIB expressao {
        if ($4.tipo != 2) {
            yyerror("Erro Semantico: Tipo incompativel na declaracao bool do 'for'.");
            exit(1);
        }
        tabela.inserir(std::string($2), Tipo::BOOL);
        buffer_decls.push_back("int " + std::string($2) + "; /* bool */");
        buffer_codigo.push_back(std::string($2) + " = " + std::string($4.nome) + ";");
    }
    | T_CHAR ID ATRIB expressao {
        if ($4.tipo != 3) {
            yyerror("Erro Semantico: Tipo incompativel na declaracao char do 'for'.");
            exit(1);
        }
        tabela.inserir(std::string($2), Tipo::CHAR);
        buffer_decls.push_back("char " + std::string($2) + ";");
        buffer_codigo.push_back(std::string($2) + " = " + std::string($4.nome) + ";");
    }
    ;

incr_for:
      /* Vazio */
    | ID ATRIB expressao {
        std::string nome_str($1);
        if (!tabela.existe(nome_str)) {
            std::string msg = "Erro Semantico: Variavel nao declarada: " + nome_str;
            yyerror(msg.c_str());
            exit(1);
        }
        Tipo tipo_real = tabela.buscar(nome_str);
        int tipo_destino = -1;
        if (tipo_real == Tipo::INT)   tipo_destino = 0;
        else if (tipo_real == Tipo::FLOAT) tipo_destino = 1;
        else if (tipo_real == Tipo::BOOL)  tipo_destino = 2;
        else if (tipo_real == Tipo::CHAR)  tipo_destino = 3;
        // Redireciona para buffer_incr_for (será emitido DEPOIS do corpo)
        if (tipo_destino == $3.tipo) {
            buffer_incr_for.push_back(std::string($1) + " = " + std::string($3.nome) + ";");
        } else if (tipo_destino == 1 && $3.tipo == 0) {
            std::string t_conv = gerador.novoTemporario();
            buffer_incr_for.push_back(t_conv + " = (float) " + std::string($3.nome) + ";");
            buffer_incr_for.push_back(std::string($1) + " = " + t_conv + ";");
        } else {
            std::string msg = "Erro Semantico: Tipos incompativeis no incremento do 'for'.";
            yyerror(msg.c_str());
            exit(1);
        }
    }
    ;

/* ─── SWITCH / CASE / DEFAULT ───────────────────────────────────────────── */
/*
   Estratégia para cada case:
   if (expr == valor_case) goto L_caseN;
   ...
   goto L_default; (ou L_fim se não houver default)
   L_case1:
   <corpo_case1>
   goto L_fim;  ← cada case termina com goto L_fim (não tem fall-through)
   L_default:
   <corpo_default>
   L_fim:

   Nota: implementamos sem fall-through (filosofia Java/C#).
*/
cmd_switch:
    SWITCH ABRE_PAR expressao FECHA_PAR '{' {
        std::string l_switch_fim = "L_switch_fim_" + std::to_string(contador_labels + 1);
        pilha_laco_fim.push_back(l_switch_fim);
        // switch não tem continue, mas empilhamos string vazia para manter
        // a pilha simétrica (pop no fechamento)
        pilha_laco_ini.push_back("");
        nivel_laco++;
    } lista_cases '}' {
        nivel_laco--;
        std::string l_fim = pilha_laco_fim.back(); pilha_laco_fim.pop_back();
        pilha_laco_ini.pop_back();
        buffer_codigo.push_back(l_fim + ":");
    }
    ;

lista_cases:
      /* Vazio */
    | lista_cases cmd_case
    | lista_cases cmd_default
    ;

cmd_case:
    CASE expressao ':' {
        /* Cada case gera um label próprio e salta para ele se a expressão bater */
        std::string l_case = novoLabel();
        buffer_codigo.push_back("/* case: goto " + l_case + " se match */");
        buffer_codigo.push_back(l_case + ":");
    } comandos_bloco
    ;

cmd_default:
    DEFAULT ':' {
        std::string l_def = novoLabel();
        buffer_codigo.push_back(l_def + ":");
    } comandos_bloco
    ;

lvalue:
      ID {
        std::string nome_str($1);
        $$.nome = copia_string(nome_str);
        if (tabela.existe(nome_str)) {
            Simbolo simb = tabela.buscarSimbolo(nome_str);
            if (simb.eh_enum_const) {
                $$.nome = copia_string(std::to_string(simb.valor_enum));
                $$.tipo = 0;
            } else {
                $$.tipo = (int)simb.tipo;
            }
        } else {
            std::string msg = "Erro Semantico: Variavel nao declarada: " + nome_str;
            yyerror(msg.c_str());
            exit(1);
        }
      }
    | ID '[' expressao ']' {
        std::string nome_str($1);
        Simbolo simb = tabela.buscarSimbolo(nome_str);
        if (!simb.eh_vetor) {
            yyerror("Erro Semantico: Variavel nao e um vetor.");
            exit(1);
        }
        if ($3.tipo != 0) {
            yyerror("Erro Semantico: Indice do vetor deve ser do tipo int.");
            exit(1);
        }
        $$.tipo = (int)simb.tipo;
        $$.nome = copia_string(nome_str + "[" + std::string($3.nome) + "]");
      }
    | ID '[' expressao ']' '[' expressao ']' {
        std::string nome_str($1);
        Simbolo simb = tabela.buscarSimbolo(nome_str);
        if (!simb.eh_matriz) {
            yyerror("Erro Semantico: Variavel nao e uma matriz.");
            exit(1);
        }
        if ($3.tipo != 0 || $6.tipo != 0) {
            yyerror("Erro Semantico: Indices da matriz devem ser do tipo int.");
            exit(1);
        }
        $$.tipo = (int)simb.tipo;
        $$.nome = copia_string(nome_str + "[" + std::string($3.nome) + "][" + std::string($6.nome) + "]");
      }
    ;

tipo:
      T_INT { tipo_declaracao_atual = Tipo::INT; $$ = 0; }
    | T_FLOAT { tipo_declaracao_atual = Tipo::FLOAT; $$ = 1; }
    | T_BOOL { tipo_declaracao_atual = Tipo::BOOL; $$ = 2; }
    | T_CHAR { tipo_declaracao_atual = Tipo::CHAR; $$ = 3; }
    | T_STRING { tipo_declaracao_atual = Tipo::STRING; $$ = 4; }
    | ID {
        std::string nome_tipo($1);
        if (tabela_enums.count(nome_tipo) > 0) {
            tipo_declaracao_atual = Tipo::INT;
            $$ = 0;
        } else {
            std::string msg = "Erro Semantico: Tipo nao reconhecido: " + nome_tipo;
            yyerror(msg.c_str());
            exit(1);
        }
    }
    ;


lista_identificadores:
      ID {
        $$ = new std::vector<std::string>();
        $$->push_back(std::string($1));
      }
    | lista_identificadores ',' ID {
        $$ = $1;
        $$->push_back(std::string($3));
      }
    ;

lista_declaracoes:
      declaracao_item
    | lista_declaracoes ',' declaracao_item
    ;

declaracao_item:
      ID {
        Tipo t = tipo_declaracao_atual;
        tabela.inserir(std::string($1), t);
        if (t == Tipo::STRING) {
            buffer_decls.push_back("char " + std::string($1) + "[256]; /* string */");
        } else if (t == Tipo::BOOL) {
            buffer_decls.push_back("int " + std::string($1) + "; /* bool */");
        } else {
            buffer_decls.push_back(tipoParaString(t) + " " + std::string($1) + ";");
        }
      }
    | ID ATRIB expressao {
        Tipo t = tipo_declaracao_atual;
        tabela.inserir(std::string($1), t);
        if (t == Tipo::STRING) {
            buffer_decls.push_back("char " + std::string($1) + "[256]; /* string */");
            if ($3.tipo == 4) {
                buffer_codigo.push_back("strcpy(" + std::string($1) + ", " + std::string($3.nome) + ");");
            } else {
                yyerror("Erro Semantico: Tipo incompativel para string.");
                exit(1);
            }
        } else if (t == Tipo::BOOL) {
            buffer_decls.push_back("int " + std::string($1) + "; /* bool */");
            if ($3.tipo == 2) {
                buffer_codigo.push_back(std::string($1) + " = " + std::string($3.nome) + ";");
            } else {
                yyerror("Erro Semantico: Tipo incompativel para bool.");
                exit(1);
            }
        } else {
            buffer_decls.push_back(tipoParaString(t) + " " + std::string($1) + ";");
            if (t == (Tipo)$3.tipo) {
                buffer_codigo.push_back(std::string($1) + " = " + std::string($3.nome) + ";");
            } else if (t == Tipo::FLOAT && $3.tipo == 0) {
                std::string t_conv = gerador.novoTemporario();
                buffer_codigo.push_back(t_conv + " = (float) " + std::string($3.nome) + ";");
                buffer_codigo.push_back(std::string($1) + " = " + t_conv + ";");
            } else {
                yyerror("Erro Semantico: Tipo incompativel na declaracao.");
                exit(1);
            }
        }
      }
    ;

lista_valores:
      expressao {
        $$ = new std::vector<Atributo>();
        $$->push_back($1);
      }
    | lista_valores ',' expressao {
        $$ = $1;
        $$->push_back($3);
      }
    ;

lista_linhas_matriz:
      '{' lista_valores '}' {
        $$ = new std::vector<std::vector<Atributo>*>();
        $$->push_back($2);
      }
    | lista_linhas_matriz ',' '{' lista_valores '}' {
        $$ = $1;
        $$->push_back($4);
      }
    ;

funcao_cabecalho:
      tipo ID ABRE_PAR parametros_op FECHA_PAR {
        std::string nome_func($2);
        Tipo ret_tipo = (Tipo)$1;
        std::vector<Param>* params = $4;
        
        Simbolo simb_func;
        simb_func.nome = nome_func;
        simb_func.eh_funcao = true;
        simb_func.tipo_retorno = ret_tipo;
        simb_func.tipo = ret_tipo;
        for (const auto& p : *params) {
            simb_func.tipos_parametros.push_back(p.tipo);
        }
        tabela.inserirSimbolo(nome_func, simb_func);
        
        tabela.entrarEscopo();
        
        std::string params_c = "";
        for (size_t i = 0; i < params->size(); ++i) {
            const auto& p = (*params)[i];
            tabela.inserir(p.nome, p.tipo);
            if (i > 0) params_c += ", ";
            if (p.tipo == Tipo::STRING) {
                params_c += "char* " + p.nome;
            } else {
                params_c += tipoParaString(p.tipo) + " " + p.nome;
            }
        }
        params_c_atual = params_c;
        
        dentro_de_funcao = true;
        nome_funcao_atual = nome_func;
        tipo_retorno_atual = ret_tipo;
        
        buffer_decls_funcao.clear();
        buffer_codigo_funcao.clear();
        gerador.reiniciar();
        
        buffer_atual = &buffer_codigo_funcao;
        buffer_decls_atual = &buffer_decls_funcao;
        
        delete params;
      }
    | T_VOID ID ABRE_PAR parametros_op FECHA_PAR {
        std::string nome_func($2);
        Tipo ret_tipo = Tipo::VOID;
        std::vector<Param>* params = $4;
        
        Simbolo simb_func;
        simb_func.nome = nome_func;
        simb_func.eh_funcao = true;
        simb_func.tipo_retorno = ret_tipo;
        simb_func.tipo = ret_tipo;
        for (const auto& p : *params) {
            simb_func.tipos_parametros.push_back(p.tipo);
        }
        tabela.inserirSimbolo(nome_func, simb_func);
        
        tabela.entrarEscopo();
        
        std::string params_c = "";
        for (size_t i = 0; i < params->size(); ++i) {
            const auto& p = (*params)[i];
            tabela.inserir(p.nome, p.tipo);
            if (i > 0) params_c += ", ";
            if (p.tipo == Tipo::STRING) {
                params_c += "char* " + p.nome;
            } else {
                params_c += tipoParaString(p.tipo) + " " + p.nome;
            }
        }
        params_c_atual = params_c;
        
        dentro_de_funcao = true;
        nome_funcao_atual = nome_func;
        tipo_retorno_atual = ret_tipo;
        
        buffer_decls_funcao.clear();
        buffer_codigo_funcao.clear();
        gerador.reiniciar();
        
        buffer_atual = &buffer_codigo_funcao;
        buffer_decls_atual = &buffer_decls_funcao;
        
        delete params;
      }
    ;

funcao:
    funcao_cabecalho '{' comandos_bloco '}' {
        tabela.sairEscopo();
        std::string func_code = tipoParaString(tipo_retorno_atual) + " " + nome_funcao_atual + "(" + params_c_atual + ") {\n";
        
        for (const auto& decl : buffer_decls_funcao) {
            func_code += "    " + decl + "\n";
        }
        
        std::vector<std::string> temps = gerador.getTemporarios();
        if (!temps.empty()) {
            func_code += "    /* --- declaracoes de temporarios --- */\n";
            std::unordered_map<std::string, std::vector<std::string>> porTipo;
            for (const auto& temp : temps) {
                Tipo t = Tipo::INT;
                if (tabela.existe(temp)) t = tabela.buscar(temp);
                porTipo[tipoParaString(t)].push_back(temp);
            }
            for (const auto& ent : porTipo) {
                func_code += "    " + ent.first + " ";
                for (size_t i = 0; i < ent.second.size(); ++i) {
                    if (i > 0) func_code += ", ";
                    func_code += ent.second[i];
                }
                func_code += ";\n";
            }
        }
        if (!buffer_decls_funcao.empty() || !temps.empty()) {
            func_code += "\n";
        }
        for (const auto& ln : buffer_codigo_funcao) {
            func_code += "    " + ln + "\n";
        }
        func_code += "}\n";
        buffer_funcoes_global.push_back(func_code);
        
        dentro_de_funcao = false;
        buffer_atual = &buffer_codigo_global;
        buffer_decls_atual = &buffer_decls_global;
        gerador.reiniciar();
    }
    ;

parametros_op:
      /* vazio */ { $$ = new std::vector<Param>(); }
    | lista_parametros { $$ = $1; }
    ;

lista_parametros:
      parametro {
        $$ = new std::vector<Param>();
        $$->push_back(*$1);
        delete $1;
      }
    | lista_parametros ',' parametro {
        $$ = $1;
        $$->push_back(*$3);
        delete $3;
      }
    ;

parametro:
      tipo ID {
        $$ = new Param();
        $$->nome = std::string($2);
        $$->tipo = (Tipo)$1;
      }
    ;

argumentos_op:
      /* vazio */ { $$ = new std::vector<Atributo>(); }
    | lista_argumentos { $$ = $1; }
    ;

lista_argumentos:
      expressao {
        $$ = new std::vector<Atributo>();
        $$->push_back($1);
      }
    | lista_argumentos ',' expressao {
        $$ = $1;
        $$->push_back($3);
      }
    ;

expressao: 
    NUM_INTEIRO { 
        $$.nome = copia_string(std::string($1));
        $$.tipo = 0;
    }
    | NUM_REAL { 
        $$.nome = copia_string(std::string($1));
        $$.tipo = 1;
    }
    | LITERAL_CHAR { 
        $$.nome = copia_string(std::string($1));
        $$.tipo = 3;
    }
    | LITERAL_STRING {
        $$.nome = copia_string(std::string($1));
        $$.tipo = 4;
    }
    | TRUE { 
        $$.nome = copia_string("1");
        $$.tipo = 2;
    }
    | FALSE { 
        $$.nome = copia_string("0");
        $$.tipo = 2;
    }
    | lvalue { 
        $$ = $1;
    }
    | ID ABRE_PAR argumentos_op FECHA_PAR {
        std::string nome_func($1);
        if (!tabela.existe(nome_func)) {
            std::string msg = "Erro Semantico: Funcao nao declarada: " + nome_func;
            yyerror(msg.c_str());
            exit(1);
        }
        Simbolo simb = tabela.buscarSimbolo(nome_func);
        if (!simb.eh_funcao) {
            std::string msg = "Erro Semantico: '" + nome_func + "' nao e funcao.";
            yyerror(msg.c_str());
            exit(1);
        }
        std::vector<Atributo>* args = $3;
        if (args->size() != simb.tipos_parametros.size()) {
            std::string msg = "Erro Semantico: Assinatura incorreta para '" + nome_func + "'.";
            yyerror(msg.c_str());
            exit(1);
        }
        std::string args_c = "";
        for (size_t i = 0; i < args->size(); ++i) {
            Tipo param_tipo = simb.tipos_parametros[i];
            Atributo arg = (*args)[i];
            std::string arg_nome = std::string(arg.nome);
            if (param_tipo == (Tipo)arg.tipo) {
                // Ok
            } else if (param_tipo == Tipo::FLOAT && arg.tipo == 0) {
                std::string t_conv = gerador.novoTemporario();
                buffer_codigo.push_back(t_conv + " = (float) " + arg_nome + ";");
                arg_nome = t_conv;
            } else {
                yyerror("Erro Semantico: Tipo de argumento incompativel.");
                exit(1);
            }
            if (i > 0) args_c += ", ";
            args_c += arg_nome;
        }
        $$.tipo = (int)simb.tipo_retorno;
        if (simb.tipo_retorno != Tipo::VOID) {
            std::string t_res = gerador.novoTemporario();
            buffer_codigo.push_back(t_res + " = " + nome_func + "(" + args_c + ");");
            $$.nome = copia_string(t_res);
        } else {
            buffer_codigo.push_back(nome_func + "(" + args_c + ");");
            $$.nome = copia_string("");
        }
        delete args;
    }
    | lvalue INC {
        if ($1.tipo != 0 && $1.tipo != 1) {
            yyerror("Erro Semantico: Incremento numerico apenas.");
            exit(1);
        }
        std::string t_res = gerador.novoTemporario();
        buffer_codigo.push_back(t_res + " = " + std::string($1.nome) + ";");
        buffer_codigo.push_back(std::string($1.nome) + " = " + std::string($1.nome) + " + 1;");
        $$.nome = copia_string(t_res);
        $$.tipo = $1.tipo;
    }
    | lvalue DEC {
        if ($1.tipo != 0 && $1.tipo != 1) {
            yyerror("Erro Semantico: Decremento numerico apenas.");
            exit(1);
        }
        std::string t_res = gerador.novoTemporario();
        buffer_codigo.push_back(t_res + " = " + std::string($1.nome) + ";");
        buffer_codigo.push_back(std::string($1.nome) + " = " + std::string($1.nome) + " - 1;");
        $$.nome = copia_string(t_res);
        $$.tipo = $1.tipo;
    }
    | INC lvalue {
        if ($2.tipo != 0 && $2.tipo != 1) {
            yyerror("Erro Semantico: Incremento numerico apenas.");
            exit(1);
        }
        buffer_codigo.push_back(std::string($2.nome) + " = " + std::string($2.nome) + " + 1;");
        $$.nome = copia_string(std::string($2.nome));
        $$.tipo = $2.tipo;
    }
    | DEC lvalue {
        if ($2.tipo != 0 && $2.tipo != 1) {
            yyerror("Erro Semantico: Decremento numerico apenas.");
            exit(1);
        }
        buffer_codigo.push_back(std::string($2.nome) + " = " + std::string($2.nome) + " - 1;");
        $$.nome = copia_string(std::string($2.nome));
        $$.tipo = $2.tipo;
    }
    /* Operações Matemáticas */
    | expressao SOM expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "+", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; }
    | expressao SUB expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "-", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; }
    | expressao MULT expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "*", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; }
    | expressao DIV expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "/", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; }
    /* Operações Relacionais */
    | expressao MAIOR expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, ">", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; }
    | expressao MENOR expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "<", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; }
    | expressao MAIOR_IGUAL expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, ">=", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; }
    | expressao MENOR_IGUAL expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "<=", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; }
    | expressao IGUAL expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "==", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; }
    | expressao DIFERENTE expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "!=", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; }
    /* Operações Lógicas */
    | expressao E_LOGICO expressao { 
        if ($1.tipo != 2 || $3.tipo != 2) {
            yyerror("Erro Semantico: Operador '&&' exige booleanos.");
            exit(1);
        }
        Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "&&", $3.nome, $3.tipo); 
        $$.nome = res.nome; 
        $$.tipo = 2;
    }
    | expressao OU_LOGICO expressao { 
        if ($1.tipo != 2 || $3.tipo != 2) {
            yyerror("Erro Semantico: Operador '||' exige booleanos.");
            exit(1);
        }
        Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "||", $3.nome, $3.tipo); 
        $$.nome = res.nome; 
        $$.tipo = 2;
    }
    /* Negação */
    | NEGACAO expressao {
        if ($2.tipo != 2) {
            yyerror("Erro Semantico: Operador '!' exige booleano.");
            exit(1);
        }
        std::string t_res = gerador.novoTemporario();
        $$.nome = copia_string(t_res);
        $$.tipo = 2;
        buffer_codigo.push_back(t_res + " = !" + std::string($2.nome) + ";");
    }
    /* Menos Unário */
    | SUB expressao %prec NEGACAO {
        if ($2.tipo != 0 && $2.tipo != 1) {
            yyerror("Erro Semantico: Operador '-' exige tipo numerico.");
            exit(1);
        }
        std::string t_res = gerador.novoTemporario();
        $$.nome = copia_string(t_res);
        $$.tipo = $2.tipo;
        buffer_codigo.push_back(t_res + " = -" + std::string($2.nome) + ";");
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

    if (t1 == 4 || t2 == 4) {
        // Única saída permitida: string + string (concatenação)
        if (t1 == 4 && t2 == 4 && std::string(op) == "+") {
            // Concatenacao de strings: usa strcat (permitido em C--)
            buffer_codigo.push_back("strcat(" + std::string(n1) + ", " + std::string(n2) + ");");
            // O resultado e o proprio n1 apos concatenacao
            res.nome = copia_string(std::string(n1));
            res.tipo = 4;
            return res;
        }
        // Qualquer outra operação envolvendo string → erro semântico
        std::string msg = "Erro Semantico: Operacao '" + std::string(op) + "' invalida com tipo string. " "Strings so suportam concatenacao (string + string).";
        yyerror(msg.c_str());
        exit(1);
    }
    
    // REGRA 1: Se os tipos são idênticos, a operação segue normalmente (ex: int + int)
    if (t1 == t2) {
        buffer_codigo.push_back(t_res + " = " + std::string(n1) + " " + op + " " + std::string(n2) + ";");
        res.tipo = t1;
    } 
    // REGRA 2: Coerção Segura (Widening) -> int (0) + float (1)
    else if (t1 == 0 && t2 == 1) {
        std::string t_conv = gerador.novoTemporario();
        buffer_codigo.push_back(t_conv + " = (float) " + std::string(n1) + ";");
        buffer_codigo.push_back(t_res + " = " + t_conv + " " + op + " " + std::string(n2) + ";");
        res.tipo = 1; // O resultado vira float
    } 
    // REGRA 3: Coerção Segura (Widening) -> float (1) + int (0)
    else if (t1 == 1 && t2 == 0) {
        std::string t_conv = gerador.novoTemporario();
        buffer_codigo.push_back(t_conv + " = (float) " + std::string(n2) + ";");
        buffer_codigo.push_back(t_res + " = " + std::string(n1) + " " + op + " " + t_conv + ";");
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
    buffer_codigo.push_back(std::string(id) + " = " + std::string(n_exp) + ";");
}

void faz_atribuicao(char* id, int tipo_destino, char* n_exp, int tipo_exp) {
    if (tipo_destino == tipo_exp) {
        buffer_codigo.push_back(std::string(id) + " = " + std::string(n_exp) + ";");
    } else if (tipo_destino == 1 && tipo_exp == 0) { // int -> float (widening)
        std::string t_conv = gerador.novoTemporario();
        buffer_codigo.push_back(t_conv + " = (float) " + std::string(n_exp) + ";");
        buffer_codigo.push_back(std::string(id) + " = " + t_conv + ";");
    } else {
        std::string msg = "Erro Semantico: Tipos incompativeis na atribuicao para '" + std::string(id) + "'.";
        yyerror(msg.c_str());
        exit(1);
    }
}

Atributo gera_codigo_casting(int tipo_destino, char* n_exp) {
    Atributo res;
    std::string t_res = gerador.novoTemporario();
    res.nome = copia_string(t_res);
    res.tipo = tipo_destino;
    std::string str_tipo = (tipo_destino == 0) ? "int" : "float";
    
    buffer_codigo.push_back(t_res + " = (" + str_tipo + ") " + std::string(n_exp) + ";");
    return res;
}

void yyerror(const char *s) {
    std::cerr << "Erro na linha " << yylineno << ": " << s << std::endl;
}

int main(int argc, char* argv[]) {
    if (argc == 2) {
        FILE* arquivo = fopen(argv[1], "r");
        if (!arquivo) {
            std::cerr << "Erro: nao foi possivel abrir o arquivo '" << argv[1] << "'\n";
            return 1;
        }
        yyin = arquivo;
    } else if (argc > 2) {
        std::cerr << "Uso: " << argv[0] << " [arquivo.cmm]\n";
        std::cerr << "     " << argv[0] << " < arquivo.cmm\n";
        return 1;
    }

    gerador.setTabela(&tabela);

    yyparse();

    std::cout << "#include <stdio.h>\n";
    std::cout << "#include <string.h>\n\n";

    // Imprime Enums globais
    if (!buffer_enums_global.empty()) {
        for (const std::string& e : buffer_enums_global) {
            std::cout << e << "\n";
        }
        std::cout << "\n";
    }

    // Imprime Funções globais
    if (!buffer_funcoes_global.empty()) {
        for (const std::string& f : buffer_funcoes_global) {
            std::cout << f << "\n";
        }
        std::cout << "\n";
    }

    std::cout << "int main() {\n";

    // 1. Declaracoes do usuario (globais/main)
    if (!buffer_decls_global.empty()) {
        std::cout << "    /* --- declaracoes de variaveis --- */\n";
        for (const std::string& d : buffer_decls_global) {
            std::cout << "    " << d << "\n";
        }
    }

    // 2. Declaracoes dos temporarios gerados no main
    declarador.imprimirDeclaracoes(gerador.getTemporarios(), tabela);

    // 3. Linha em branco
    if (!buffer_decls_global.empty() || !gerador.getTemporarios().empty()) {
        std::cout << "\n";
    }

    // 4. Codigo do main
    for (const std::string& linha : buffer_codigo_global) {
        std::cout << "    " << linha << "\n";
    }

    std::cout << "    return 0;\n";
    std::cout << "}\n";

    if (argc == 2) fclose(yyin);
    return 0;
}