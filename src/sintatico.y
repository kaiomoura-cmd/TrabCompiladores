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

// ─── Flag de erro global ─────────────────────────────────────────────────────
// Qualquer erro (sintático ou semântico) marca esta flag.
// O main() checa antes de emitir o código C — se houve erro, não emite nada.
bool houve_erro = false;
std::string nome_arquivo_atual = "";

// ─── Cores ANSI para mensagens de erro no stderr ─────────────────────────────
static const char* COR_RESET   = "\033[0m";
static const char* COR_NEGRITO = "\033[1m";
static const char* COR_VERM    = "\033[1;31m";  // vermelho negrito (erro)
static const char* COR_AMAR    = "\033[1;33m";  // amarelo (detalhe)
static const char* COR_CIANO   = "\033[1;36m";  // ciano (info)


// ─── Gerador de Labels (L1, L2, L3, ...) ──────────────────────────────────
static int contador_labels = 0;
std::string novoLabel() {
    return "L" + std::to_string(++contador_labels);
}

// ─── Contador de profundidade de laço (para validar break/continue) ────────
static int nivel_laco = 0;
static int nivel_loop_puro = 0; // conta apenas while/for (não switch) — usado pelo continue

std::vector<std::string> pilha_labels_fim;   
std::vector<std::string> pilha_labels_ini;   
std::vector<std::string> pilha_laco_fim;   
std::vector<std::string> pilha_laco_ini;   

// Pilha de buffers de incremento do for (suporta for aninhados)
std::vector<std::vector<std::string>> pilha_incr_for;

// Suporte ao switch/case — pilhas para switches aninhados
std::vector<size_t>                   pilha_switch_dispatch_index;
std::vector<std::vector<std::string>> pilha_switch_dispatch;
std::vector<std::string>              pilha_switch_temp;
std::vector<std::string>              pilha_switch_default_label;

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
    char* nome_orig;
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
// Gera printfs separados seguindo a diretriz de 3 endereços:
//   "prefixo%spec sufixo" + var → printf("prefixo") + printf("%spec", var) + printf(" sufixo")
void gera_write_formato(const std::string& formato_raw, const std::string& var_nome);
}

%define parse.error verbose

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
        Simbolo simb_inserido = tabela.buscarSimbolo(nome_var);
        buffer_decls.push_back(tipoParaString(t) + " " + simb_inserido.nome_c + "[" + std::to_string(dim) + "];");
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
        Simbolo simb_inserido = tabela.buscarSimbolo(nome_var);
        buffer_decls.push_back(tipoParaString(t) + " " + simb_inserido.nome_c + "[" + std::to_string(dim1) + "][" + std::to_string(dim2) + "];");
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
        Simbolo simb;
        simb.nome = nome_var;
        simb.tipo = t;
        simb.eh_vetor = true;
        simb.dim1 = dim;
        tabela.inserirSimbolo(nome_var, simb);
        Simbolo simb_inserido = tabela.buscarSimbolo(nome_var);
        
        // Declaracao sem inicializacao
        buffer_decls.push_back(tipoParaString(t) + " " + simb_inserido.nome_c + "[" + std::to_string(dim) + "];");
        
        // Atribuicoes atômicas elemento a elemento
        for (size_t i = 0; i < vals->size(); ++i) {
            if (t != (Tipo)(*vals)[i].tipo) {
                yyerror("Erro Semantico: Inicializador com tipo incompativel.");
                exit(1);
            }
            buffer_codigo.push_back(simb_inserido.nome_c + "[" + std::to_string(i) + "] = " + (*vals)[i].nome + ";");
        }
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
        Simbolo simb;
        simb.nome = nome_var;
        simb.tipo = t;
        simb.eh_matriz = true;
        simb.dim1 = dim1;
        simb.dim2 = dim2;
        tabela.inserirSimbolo(nome_var, simb);
        Simbolo simb_inserido = tabela.buscarSimbolo(nome_var);
        
        // Declaracao sem inicializacao
        buffer_decls.push_back(tipoParaString(t) + " " + simb_inserido.nome_c + "[" + std::to_string(dim1) + "][" + std::to_string(dim2) + "];");
        
        // Atribuicoes atômicas celula a celula
        for (size_t r = 0; r < linhas->size(); ++r) {
            std::vector<Atributo>* cols = (*linhas)[r];
            if (cols->size() > (size_t)dim2) {
                yyerror("Erro Semantico: Numero de colunas maior que dim2.");
                exit(1);
            }
            for (size_t c = 0; c < cols->size(); ++c) {
                if (t != (Tipo)(*cols)[c].tipo) {
                    yyerror("Erro Semantico: Tipo de valor invalido na inicializacao da matriz.");
                    exit(1);
                }
                buffer_codigo.push_back(simb_inserido.nome_c + "[" + std::to_string(r) + "][" + std::to_string(c) + "] = " + (*cols)[c].nome + ";");
            }
            delete cols;
        }
        delete linhas;
    }
    /* Atribuicao padrao */
    | lvalue ATRIB expressao ';' {
        std::string lval_nome($1.nome);
        int tipo_dest = $1.tipo;
        if (tipo_dest == $3.tipo) {
            if (tipo_dest == 4) {
                buffer_codigo.push_back("free(" + lval_nome + ");");
                buffer_codigo.push_back(lval_nome + " = malloc(strlen(" + std::string($3.nome) + ") + 1);");
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
        std::string dest($1.nome); // nome_c
        std::string src($3); // nome original
        if (!tabela.existe(src)) {
            yyerror("Erro Semantico: Vetor nao encontrado.");
            exit(1);
        }
        Simbolo simb_src = tabela.buscarSimbolo(src);
        if (!simb_src.eh_vetor) {
            yyerror("Erro Semantico: Slice exige vetor de origem.");
            exit(1);
        }
        std::string dest_orig($1.nome_orig); // nome original
        Simbolo simb_dest = tabela.buscarSimbolo(dest_orig);
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
        buffer_codigo.push_back("    " + dest + "[" + t_sl + "] = " + simb_src.nome_c + "[" + std::string($5.nome) + " + " + t_sl + "];");
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
                bool declared = false;
                for (const auto& decl : buffer_decls) {
                    if (decl.find("t_read_buf") != std::string::npos) {
                        declared = true;
                        break;
                    }
                }
                if (!declared) {
                    buffer_decls.push_back("char t_read_buf[1024];");
                }
                buffer_codigo.push_back("scanf(\"" + fmt + "\", t_read_buf);");
                buffer_codigo.push_back("free(" + nome_str + ");");
                buffer_codigo.push_back(nome_str + " = malloc(strlen(t_read_buf) + 1);");
                buffer_codigo.push_back("strcpy(" + nome_str + ", t_read_buf);");
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
    /* write com formato customizado: write("prefixo %spec sufixo", expr)
       Gera printfs separados (3-address code):
         printf("prefixo");          ← literal puro, sem variável
         printf("%spec", var);       ← endereço da variável
         printf(" sufixo");          ← literal puro, sem variável              */
    | WRITE ABRE_PAR LITERAL_STRING ',' expressao FECHA_PAR ';' {
            std::string formato($3);
            // Remove as aspas externas do literal (ex: "\"hello\"" → "hello")
            if (formato.size() >= 2 && formato.front() == '"' && formato.back() == '"') {
                formato = formato.substr(1, formato.size() - 2);
            }
            gera_write_formato(formato, std::string($5.nome));
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
            buffer_codigo.push_back("    printf(\"%d\", " + simb.nome_c + "[" + std::string($5.nome) + " + " + t_sl + "]);");
        } else if (simb.tipo == Tipo::FLOAT) {
            buffer_codigo.push_back("    printf(\"%f\", " + simb.nome_c + "[" + std::string($5.nome) + " + " + t_sl + "]);");
        } else if (simb.tipo == Tipo::CHAR) {
            buffer_codigo.push_back("    printf(\"%c\", " + simb.nome_c + "[" + std::string($5.nome) + " + " + t_sl + "]);");
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
            if (nivel_loop_puro == 0) {
                yyerror("Erro Semantico: 'continue' usado fora de um laco (nao e valido dentro de switch).");
                exit(1);
            }
            /* Usa a pilha EXCLUSIVA de laços — ignora labels de if e switch aninhados */
            buffer_codigo.push_back("goto " + pilha_laco_ini.back() + ";");
        }
    | expressao ';' 
    | bloco
    ;

/* Regras de Escopo (Blocos de código) */
bloco:
      '{' { 
          tabela.entrarEscopo(); 
        } comandos_bloco '}' { 
          tabela.sairEscopo(); 
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
        nivel_loop_puro++;
    } comando {
        nivel_laco--;
        nivel_loop_puro--;
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
    FOR ABRE_PAR { tabela.entrarEscopo(); } init_for ';' label_for_inicio expressao ';' {
        // ── Verificação Semântica: condição deve ser bool (tipo 2) ──
        // Nota: com a mid-rule action { entrarEscopo() } em $3, expressao passa a ser $7
        if ($7.tipo != 2) {
            yyerror("Erro Semantico: A condicao do 'for' deve ser do tipo bool.");
            exit(1);
        }
        std::string l_fim = novoLabel();
        buffer_codigo.push_back("if (!(" + std::string($7.nome) + ")) goto " + l_fim + ";");
        // Empilha nas pilhas DE LAÇO (usadas por break/continue)
        pilha_laco_fim.push_back(l_fim);
        pilha_laco_ini.push_back(pilha_labels_ini.back());
        // Empilha um buffer de incremento exclusivo para este for (suporta for aninhados)
        pilha_incr_for.push_back(std::vector<std::string>());
    } incr_for FECHA_PAR {
        nivel_laco++;
        nivel_loop_puro++;
    } comando {
        nivel_laco--;
        nivel_loop_puro--;
        // Emite o incremento (capturado no buffer deste for) após o corpo
        for (const auto& linha : pilha_incr_for.back()) {
            buffer_codigo.push_back(linha);
        }
        pilha_incr_for.pop_back();
        std::string l_fim = pilha_laco_fim.back(); pilha_laco_fim.pop_back();
        pilha_laco_ini.pop_back();
        std::string l_ini = pilha_labels_ini.back(); pilha_labels_ini.pop_back();
        buffer_codigo.push_back("goto " + l_ini + ";");
        buffer_codigo.push_back(l_fim + ":");
        tabela.sairEscopo();
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
        Simbolo simb = tabela.buscarSimbolo(nome_str);
        int tipo_destino = -1;
        if (tipo_real == Tipo::INT)   tipo_destino = 0;
        else if (tipo_real == Tipo::FLOAT) tipo_destino = 1;
        else if (tipo_real == Tipo::BOOL)  tipo_destino = 2;
        else if (tipo_real == Tipo::CHAR)  tipo_destino = 3;
        faz_atribuicao(const_cast<char*>(simb.nome_c.c_str()), tipo_destino, $3.nome, $3.tipo);
    }
    /* Fix 2: for com declaracao inline — for(int i = 0; ...) */
    | T_INT ID ATRIB expressao {
        if ($4.tipo != 0) {
            yyerror("Erro Semantico: Tipo incompativel na declaracao int do 'for'.");
            exit(1);
        }
        tabela.inserir(std::string($2), Tipo::INT);
        Simbolo simb = tabela.buscarSimbolo(std::string($2));
        buffer_decls.push_back("int " + simb.nome_c + ";");
        buffer_codigo.push_back(simb.nome_c + " = " + std::string($4.nome) + ";");
    }
    | T_FLOAT ID ATRIB expressao {
        tabela.inserir(std::string($2), Tipo::FLOAT);
        Simbolo simb = tabela.buscarSimbolo(std::string($2));
        buffer_decls.push_back("float " + simb.nome_c + ";");
        if ($4.tipo == 1) {
            buffer_codigo.push_back(simb.nome_c + " = " + std::string($4.nome) + ";");
        } else if ($4.tipo == 0) {
            std::string t_conv = gerador.novoTemporario();
            buffer_codigo.push_back(t_conv + " = (float) " + std::string($4.nome) + ";");
            buffer_codigo.push_back(simb.nome_c + " = " + t_conv + ";");
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
        Simbolo simb = tabela.buscarSimbolo(std::string($2));
        buffer_decls.push_back("int " + simb.nome_c + "; /* bool */");
        buffer_codigo.push_back(simb.nome_c + " = " + std::string($4.nome) + ";");
    }
    | T_CHAR ID ATRIB expressao {
        if ($4.tipo != 3) {
            yyerror("Erro Semantico: Tipo incompativel na declaracao char do 'for'.");
            exit(1);
        }
        tabela.inserir(std::string($2), Tipo::CHAR);
        Simbolo simb = tabela.buscarSimbolo(std::string($2));
        buffer_decls.push_back("char " + simb.nome_c + ";");
        buffer_codigo.push_back(simb.nome_c + " = " + std::string($4.nome) + ";");
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
        Simbolo simb = tabela.buscarSimbolo(nome_str);
        int tipo_destino = -1;
        if (tipo_real == Tipo::INT)   tipo_destino = 0;
        else if (tipo_real == Tipo::FLOAT) tipo_destino = 1;
        else if (tipo_real == Tipo::BOOL)  tipo_destino = 2;
        else if (tipo_real == Tipo::CHAR)  tipo_destino = 3;
        // Redireciona para pilha_incr_for.back() — suporta for aninhados
        if (tipo_destino == $3.tipo) {
            pilha_incr_for.back().push_back(simb.nome_c + " = " + std::string($3.nome) + ";");
        } else if (tipo_destino == 1 && $3.tipo == 0) {
            std::string t_conv = gerador.novoTemporario();
            pilha_incr_for.back().push_back(t_conv + " = (float) " + std::string($3.nome) + ";");
            pilha_incr_for.back().push_back(simb.nome_c + " = " + t_conv + ";");
        } else {
            std::string msg = "Erro Semantico: Tipos incompativeis no incremento do 'for'.";
            yyerror(msg.c_str());
            exit(1);
        }
    }
    /* Operadores unarios pos-fixados: i++, i-- */
    | ID INC {
        std::string nome_str($1);
        if (!tabela.existe(nome_str)) {
            std::string msg = "Erro Semantico: Variavel nao declarada: " + nome_str;
            yyerror(msg.c_str());
            exit(1);
        }
        Tipo tipo_real = tabela.buscar(nome_str);
        if (tipo_real != Tipo::INT && tipo_real != Tipo::FLOAT) {
            yyerror("Erro Semantico: Incremento invalido para este tipo.");
            exit(1);
        }
        Simbolo simb = tabela.buscarSimbolo(nome_str);
        pilha_incr_for.back().push_back(simb.nome_c + "++;");
    }
    | ID DEC {
        std::string nome_str($1);
        if (!tabela.existe(nome_str)) {
            std::string msg = "Erro Semantico: Variavel nao declarada: " + nome_str;
            yyerror(msg.c_str());
            exit(1);
        }
        Tipo tipo_real = tabela.buscar(nome_str);
        if (tipo_real != Tipo::INT && tipo_real != Tipo::FLOAT) {
            yyerror("Erro Semantico: Decremento invalido para este tipo.");
            exit(1);
        }
        Simbolo simb = tabela.buscarSimbolo(nome_str);
        pilha_incr_for.back().push_back(simb.nome_c + "--;");
    }
    /* Operadores unarios pre-fixados: ++i, --i */
    | INC ID {
        std::string nome_str($2);
        if (!tabela.existe(nome_str)) {
            std::string msg = "Erro Semantico: Variavel nao declarada: " + nome_str;
            yyerror(msg.c_str());
            exit(1);
        }
        Tipo tipo_real = tabela.buscar(nome_str);
        if (tipo_real != Tipo::INT && tipo_real != Tipo::FLOAT) {
            yyerror("Erro Semantico: Incremento invalido para este tipo.");
            exit(1);
        }
        Simbolo simb = tabela.buscarSimbolo(nome_str);
        pilha_incr_for.back().push_back("++" + simb.nome_c + ";");
    }
    | DEC ID {
        std::string nome_str($2);
        if (!tabela.existe(nome_str)) {
            std::string msg = "Erro Semantico: Variavel nao declarada: " + nome_str;
            yyerror(msg.c_str());
            exit(1);
        }
        Tipo tipo_real = tabela.buscar(nome_str);
        if (tipo_real != Tipo::INT && tipo_real != Tipo::FLOAT) {
            yyerror("Erro Semantico: Decremento invalido para este tipo.");
            exit(1);
        }
        Simbolo simb = tabela.buscarSimbolo(nome_str);
        pilha_incr_for.back().push_back("--" + simb.nome_c + ";");
    }
    /* Operadores compostos: i+=expr, i-=expr, i*=expr, i/=expr */
    | ID MAIS_ATRIB expressao {
        std::string nome_str($1);
        if (!tabela.existe(nome_str)) { yyerror(("Erro Semantico: Variavel nao declarada: " + nome_str).c_str()); exit(1); }
        Simbolo simb = tabela.buscarSimbolo(nome_str);
        Atributo res = gera_codigo_operacao(const_cast<char*>(simb.nome_c.c_str()), (int)simb.tipo, "+", $3.nome, $3.tipo);
        pilha_incr_for.back().push_back(simb.nome_c + " = " + std::string(res.nome) + ";");
    }
    | ID MENOS_ATRIB expressao {
        std::string nome_str($1);
        if (!tabela.existe(nome_str)) { yyerror(("Erro Semantico: Variavel nao declarada: " + nome_str).c_str()); exit(1); }
        Simbolo simb = tabela.buscarSimbolo(nome_str);
        Atributo res = gera_codigo_operacao(const_cast<char*>(simb.nome_c.c_str()), (int)simb.tipo, "-", $3.nome, $3.tipo);
        pilha_incr_for.back().push_back(simb.nome_c + " = " + std::string(res.nome) + ";");
    }
    | ID MULT_ATRIB expressao {
        std::string nome_str($1);
        if (!tabela.existe(nome_str)) { yyerror(("Erro Semantico: Variavel nao declarada: " + nome_str).c_str()); exit(1); }
        Simbolo simb = tabela.buscarSimbolo(nome_str);
        Atributo res = gera_codigo_operacao(const_cast<char*>(simb.nome_c.c_str()), (int)simb.tipo, "*", $3.nome, $3.tipo);
        pilha_incr_for.back().push_back(simb.nome_c + " = " + std::string(res.nome) + ";");
    }
    | ID DIV_ATRIB expressao {
        std::string nome_str($1);
        if (!tabela.existe(nome_str)) { yyerror(("Erro Semantico: Variavel nao declarada: " + nome_str).c_str()); exit(1); }
        Simbolo simb = tabela.buscarSimbolo(nome_str);
        Atributo res = gera_codigo_operacao(const_cast<char*>(simb.nome_c.c_str()), (int)simb.tipo, "/", $3.nome, $3.tipo);
        pilha_incr_for.back().push_back(simb.nome_c + " = " + std::string(res.nome) + ";");
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
        /* ── Estratégia de geração para switch ────────────────────────────────
           1. Avaliar a expressão em temporário t_sw
           2. Salvar o índice atual do buffer (dispatch será inserido aqui depois)
           3. Cada case adiciona "if (t_sw==val) goto L;" ao buffer de dispatch
              e emite seu corpo normalmente
           4. Ao fechar: inserir o bloco de dispatch no índice salvo via insert()
           Suporta switch aninhado via pilhas.
           ─────────────────────────────────────────────────────────────────── */
        std::string t_sw = gerador.novoTemporario();
        buffer_codigo.push_back(t_sw + " = " + std::string($3.nome) + ";");
        pilha_switch_temp.push_back(t_sw);
        // Salva posição no buffer APÓS a atribuição do temporário
        pilha_switch_dispatch_index.push_back(buffer_codigo.size());
        pilha_switch_dispatch.push_back(std::vector<std::string>());
        pilha_switch_default_label.push_back(""); // preenchido se houver default

        std::string l_fim = novoLabel();
        pilha_laco_fim.push_back(l_fim);
        // switch não tem continue — empilhamos string vazia para manter pilha simétrica
        // continue dentro de switch é bloqueado por nivel_loop_puro
        pilha_laco_ini.push_back("");
        nivel_laco++;
    } lista_cases '}' {
        nivel_laco--;
        std::string l_fim = pilha_laco_fim.back(); pilha_laco_fim.pop_back();
        pilha_laco_ini.pop_back();

        // Recupera dados do switch atual
        size_t idx                    = pilha_switch_dispatch_index.back(); pilha_switch_dispatch_index.pop_back();
        std::vector<std::string> disp = pilha_switch_dispatch.back();       pilha_switch_dispatch.pop_back();
        std::string def_lbl           = pilha_switch_default_label.back();  pilha_switch_default_label.pop_back();
        pilha_switch_temp.pop_back();

        // goto de fallthrough: vai para default (se houver) ou direto ao fim
        std::string goto_ft = def_lbl.empty()
            ? ("goto " + l_fim + ";")
            : ("goto " + def_lbl + ";");
        disp.push_back(goto_ft);

        // Insere o bloco de dispatch no índice reservado (antes dos corpos dos cases)
        buffer_codigo.insert(buffer_codigo.begin() + idx, disp.begin(), disp.end());

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
        std::string t_sw  = pilha_switch_temp.back();
        std::string l_case = novoLabel();
        // Adiciona comparação ao buffer de dispatch do switch atual
        pilha_switch_dispatch.back().push_back(
            "if (" + t_sw + " == " + std::string($2.nome) + ") goto " + l_case + ";"
        );
        // Emite o label do case no fluxo normal do código
        buffer_codigo.push_back(l_case + ":");
    } comandos_bloco
    ;

cmd_default:
    DEFAULT ':' {
        std::string l_def = novoLabel();
        // Registra label do default para o switch usar no goto de fallthrough
        pilha_switch_default_label.back() = l_def;
        buffer_codigo.push_back(l_def + ":");
    } comandos_bloco
    ;

lvalue:
      ID {
        std::string nome_str($1);
        if (tabela.existe(nome_str)) {
            Simbolo simb = tabela.buscarSimbolo(nome_str);
            if (simb.eh_enum_const) {
                $$.nome = copia_string(std::to_string(simb.valor_enum));
                $$.tipo = 0;
                $$.nome_orig = copia_string("");
            } else {
                $$.nome = copia_string(simb.nome_c);
                $$.tipo = (int)simb.tipo;
                $$.nome_orig = copia_string(nome_str);
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
        $$.nome = copia_string(simb.nome_c + "[" + std::string($3.nome) + "]");
        $$.nome_orig = copia_string(nome_str);
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
        $$.nome = copia_string(simb.nome_c + "[" + std::string($3.nome) + "][" + std::string($6.nome) + "]");
        $$.nome_orig = copia_string(nome_str);
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
        Simbolo simb = tabela.buscarSimbolo(std::string($1));
        if (t == Tipo::STRING) {
            buffer_decls.push_back("char* " + simb.nome_c + " = NULL;");
            buffer_codigo.push_back(simb.nome_c + " = malloc(1);");
            buffer_codigo.push_back(simb.nome_c + "[0] = '\\0';");
        } else if (t == Tipo::BOOL) {
            buffer_decls.push_back("int " + simb.nome_c + "; /* bool */");
        } else {
            buffer_decls.push_back(tipoParaString(t) + " " + simb.nome_c + ";");
        }
      }
    | ID ATRIB expressao {
        Tipo t = tipo_declaracao_atual;
        tabela.inserir(std::string($1), t);
        Simbolo simb = tabela.buscarSimbolo(std::string($1));
        if (t == Tipo::STRING) {
            buffer_decls.push_back("char* " + simb.nome_c + " = NULL;");
            if ($3.tipo == 4) {
                buffer_codigo.push_back(simb.nome_c + " = malloc(strlen(" + std::string($3.nome) + ") + 1);");
                buffer_codigo.push_back("strcpy(" + simb.nome_c + ", " + std::string($3.nome) + ");");
            } else {
                yyerror("Erro Semantico: Tipo incompativel para string.");
                exit(1);
            }
        } else if (t == Tipo::BOOL) {
            buffer_decls.push_back("int " + simb.nome_c + "; /* bool */");
            if ($3.tipo == 2) {
                buffer_codigo.push_back(simb.nome_c + " = " + std::string($3.nome) + ";");
            } else {
                yyerror("Erro Semantico: Tipo incompativel para bool.");
                exit(1);
            }
        } else {
            buffer_decls.push_back(tipoParaString(t) + " " + simb.nome_c + ";");
            if (t == (Tipo)$3.tipo) {
                buffer_codigo.push_back(simb.nome_c + " = " + std::string($3.nome) + ";");
            } else if (t == Tipo::FLOAT && $3.tipo == 0) {
                std::string t_conv = gerador.novoTemporario();
                buffer_codigo.push_back(t_conv + " = (float) " + std::string($3.nome) + ";");
                buffer_codigo.push_back(simb.nome_c + " = " + t_conv + ";");
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
            Simbolo simb_p = tabela.buscarSimbolo(p.nome);
            if (i > 0) params_c += ", ";
            if (p.tipo == Tipo::STRING) {
                params_c += "char* " + simb_p.nome_c;
            } else {
                params_c += tipoParaString(p.tipo) + " " + simb_p.nome_c;
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
            Simbolo simb_p = tabela.buscarSimbolo(p.nome);
            if (i > 0) params_c += ", ";
            if (p.tipo == Tipo::STRING) {
                params_c += "char* " + simb_p.nome_c;
            } else {
                params_c += tipoParaString(p.tipo) + " " + simb_p.nome_c;
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
            std::unordered_map<std::string, std::vector<std::string>> porTipo;
            bool has_temps = false;
            for (const auto& temp : temps) {
                if (tabela.existePorNomeC(temp)) {
                    continue;
                }
                has_temps = true;
                Tipo t = Tipo::INT;
                porTipo[tipoParaString(t)].push_back(temp);
            }
            if (has_temps) {
                func_code += "    /* --- declaracoes de temporarios --- */\n";
                for (const auto& ent : porTipo) {
                    func_code += "    " + ent.first + " ";
                    for (size_t i = 0; i < ent.second.size(); ++i) {
                        if (i > 0) func_code += ", ";
                        func_code += ent.second[i];
                    }
                    func_code += ";\n";
                }
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
        $$.nome_orig = copia_string("");
    }
    | NUM_REAL { 
        $$.nome = copia_string(std::string($1));
        $$.tipo = 1;
        $$.nome_orig = copia_string("");
    }
    | LITERAL_CHAR { 
        $$.nome = copia_string(std::string($1));
        $$.tipo = 3;
        $$.nome_orig = copia_string("");
    }
    | LITERAL_STRING {
        $$.nome = copia_string(std::string($1));
        $$.tipo = 4;
        $$.nome_orig = copia_string("");
    }
    | TRUE { 
        $$.nome = copia_string("1");
        $$.tipo = 2;
        $$.nome_orig = copia_string("");
    }
    | FALSE { 
        $$.nome = copia_string("0");
        $$.tipo = 2;
        $$.nome_orig = copia_string("");
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
        $$.nome_orig = copia_string("");
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
        $$.nome_orig = copia_string("");
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
        $$.nome_orig = copia_string("");
    }
    | INC lvalue {
        if ($2.tipo != 0 && $2.tipo != 1) {
            yyerror("Erro Semantico: Incremento numerico apenas.");
            exit(1);
        }
        buffer_codigo.push_back(std::string($2.nome) + " = " + std::string($2.nome) + " + 1;");
        $$.nome = copia_string(std::string($2.nome));
        $$.tipo = $2.tipo;
        $$.nome_orig = copia_string("");
    }
    | DEC lvalue {
        if ($2.tipo != 0 && $2.tipo != 1) {
            yyerror("Erro Semantico: Decremento numerico apenas.");
            exit(1);
        }
        buffer_codigo.push_back(std::string($2.nome) + " = " + std::string($2.nome) + " - 1;");
        $$.nome = copia_string(std::string($2.nome));
        $$.tipo = $2.tipo;
        $$.nome_orig = copia_string("");
    }
    /* Operações Matemáticas */
    | expressao SOM expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "+", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; $$.nome_orig = copia_string(""); }
    | expressao SUB expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "-", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; $$.nome_orig = copia_string(""); }
    | expressao MULT expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "*", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; $$.nome_orig = copia_string(""); }
    | expressao DIV expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "/", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = res.tipo; $$.nome_orig = copia_string(""); }
    /* Operações Relacionais */
    | expressao MAIOR expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, ">", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; $$.nome_orig = copia_string(""); }
    | expressao MENOR expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "<", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; $$.nome_orig = copia_string(""); }
    | expressao MAIOR_IGUAL expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, ">=", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; $$.nome_orig = copia_string(""); }
    | expressao MENOR_IGUAL expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "<=", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; $$.nome_orig = copia_string(""); }
    | expressao IGUAL expressao  { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "==", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; $$.nome_orig = copia_string(""); }
    | expressao DIFERENTE expressao { Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "!=", $3.nome, $3.tipo); $$.nome = res.nome; $$.tipo = 2; $$.nome_orig = copia_string(""); }
    /* Operações Lógicas */
    | expressao E_LOGICO expressao { 
        if ($1.tipo != 2 || $3.tipo != 2) {
            yyerror("Erro Semantico: Operador '&&' exige booleanos.");
            exit(1);
        }
        Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "&&", $3.nome, $3.tipo); 
        $$.nome = res.nome; 
        $$.tipo = 2;
        $$.nome_orig = copia_string("");
    }
    | expressao OU_LOGICO expressao { 
        if ($1.tipo != 2 || $3.tipo != 2) {
            yyerror("Erro Semantico: Operador '||' exige booleanos.");
            exit(1);
        }
        Atributo res = gera_codigo_operacao($1.nome, $1.tipo, "||", $3.nome, $3.tipo); 
        $$.nome = res.nome; 
        $$.tipo = 2;
        $$.nome_orig = copia_string("");
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
        $$.nome_orig = copia_string("");
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
        $$.nome_orig = copia_string("");
        buffer_codigo.push_back(t_res + " = -" + std::string($2.nome) + ";");
    }
    /* Casting e Parênteses */
    | ABRE_PAR T_INT FECHA_PAR expressao   { Atributo res = gera_codigo_casting(0, $4.nome); $$.nome = res.nome; $$.tipo = res.tipo; $$.nome_orig = copia_string(""); }
    | ABRE_PAR T_FLOAT FECHA_PAR expressao { Atributo res = gera_codigo_casting(1, $4.nome); $$.nome = res.nome; $$.tipo = res.tipo; $$.nome_orig = copia_string(""); }
    | ABRE_PAR expressao FECHA_PAR       { $$.nome = $2.nome; $$.tipo = $2.tipo; $$.nome_orig = $2.nome_orig; }
    ;

%%

// ─── gera_write_formato ────────────────────────────────────────────────────
// Segue estritamente a diretriz de código de 3 endereços:
// cada instrução de saída envolve no máximo um endereço (variável).
//
// Entrada:  formato_raw = string de formato sem as aspas externas (ex: "numero é: %i ")
//           var_nome    = nome C da variável (ex: "t1")
//
// Saída no buffer_codigo (exemplos):
//   printf("numero é: ");    ← instrução puramente literal (0 endereços)
//   printf("%i ", t1);       ← instrução com 1 endereço (a variável)
//
// Suporta especificadores com flags/largura/precisão: %d %i %f %s %c %u %x %o %e %g
// e também %-5d, %3.2f, etc.
// ─────────────────────────────────────────────────────────────────────────────
void gera_write_formato(const std::string& formato_raw, const std::string& var_nome) {
    // Localiza o primeiro especificador de formato (%d, %i, %f, ...)
    size_t spec_start = std::string::npos;
    size_t spec_end   = std::string::npos;

    for (size_t pos = 0; pos < formato_raw.size(); ) {
        if (formato_raw[pos] != '%') { ++pos; continue; }

        size_t s = pos;   // marca o início do possível especificador
        ++pos;
        if (pos >= formato_raw.size()) break;

        // Flags opcionais: - + ' ' # 0
        while (pos < formato_raw.size() &&
               (formato_raw[pos] == '-' || formato_raw[pos] == '+' ||
                formato_raw[pos] == ' ' || formato_raw[pos] == '#' ||
                formato_raw[pos] == '0'))
            ++pos;

        // Largura opcional (dígitos)
        while (pos < formato_raw.size() && std::isdigit((unsigned char)formato_raw[pos]))
            ++pos;

        // Precisão opcional (.dígitos)
        if (pos < formato_raw.size() && formato_raw[pos] == '.') {
            ++pos;
            while (pos < formato_raw.size() && std::isdigit((unsigned char)formato_raw[pos]))
                ++pos;
        }

        // Caractere de conversão
        if (pos < formato_raw.size()) {
            char c = formato_raw[pos];
            if (c == 'd' || c == 'i' || c == 'f' || c == 's' || c == 'c' ||
                c == 'u' || c == 'x' || c == 'o' || c == 'e' || c == 'g') {
                spec_start = s;
                spec_end   = pos;   // inclusivo
                break;
            }
        }
        // Não era um especificador válido — continua procurando
    }

    if (spec_start == std::string::npos) {
        // Nenhum especificador encontrado: emite apenas literal
        buffer_codigo.push_back("printf(\"" + formato_raw + "\");");
        return;
    }

    // ── Prefixo (texto antes do especificador) ────────────────────────────
    if (spec_start > 0) {
        std::string prefix = formato_raw.substr(0, spec_start);
        buffer_codigo.push_back("printf(\"" + prefix + "\");");
    }

    // ── Especificador + variável (único endereço) ─────────────────────────
    std::string spec = formato_raw.substr(spec_start, spec_end - spec_start + 1);
    buffer_codigo.push_back("printf(\"" + spec + "\", " + var_nome + ");");

    // ── Sufixo (texto depois do especificador) ────────────────────────────
    if (spec_end + 1 < formato_raw.size()) {
        std::string suffix = formato_raw.substr(spec_end + 1);
        buffer_codigo.push_back("printf(\"" + suffix + "\");");
    }
}

Atributo gera_codigo_operacao(char* n1, int t1, const char* op, char* n2, int t2) {
    Atributo res;
    std::string t_res = gerador.novoTemporario();
    res.nome = copia_string(t_res);

    if (t1 == 4 || t2 == 4) {
        if (t1 == 4 && t2 == 4 && std::string(op) == "+") {
            std::string t_concat = gerador.novoTemporario();
            Simbolo simb;
            simb.nome = t_concat;
            simb.nome_c = t_concat;
            simb.tipo = Tipo::STRING;
            tabela.inserirSimbolo(t_concat, simb);
            
            buffer_decls.push_back("char* " + t_concat + " = NULL;");
            
            std::string t_len1 = gerador.novoTemporario();
            std::string t_len2 = gerador.novoTemporario();
            std::string t_sum = gerador.novoTemporario();
            std::string t_sum_plus = gerador.novoTemporario();
            
            std::string lbl_skip1 = novoLabel();
            std::string lbl_skip2 = novoLabel();
            
            // Calculo do tamanho da string 1
            buffer_codigo.push_back(t_len1 + " = 0;");
            buffer_codigo.push_back("if (!" + std::string(n1) + ") goto " + lbl_skip1 + ";");
            buffer_codigo.push_back(t_len1 + " = strlen(" + std::string(n1) + ");");
            buffer_codigo.push_back(lbl_skip1 + ":");
            
            // Calculo do tamanho da string 2
            buffer_codigo.push_back(t_len2 + " = 0;");
            buffer_codigo.push_back("if (!" + std::string(n2) + ") goto " + lbl_skip2 + ";");
            buffer_codigo.push_back(t_len2 + " = strlen(" + std::string(n2) + ");");
            buffer_codigo.push_back(lbl_skip2 + ":");
            
            // Soma e incremento de 1
            buffer_codigo.push_back(t_sum + " = " + t_len1 + " + " + t_len2 + ";");
            buffer_codigo.push_back(t_sum_plus + " = " + t_sum + " + 1;");
            
            // Alocacao
            buffer_codigo.push_back(t_concat + " = malloc(" + t_sum_plus + ");");
            buffer_codigo.push_back(t_concat + "[0] = '\\0';");
            
            // Copia da primeira string
            std::string lbl_cpy = novoLabel();
            buffer_codigo.push_back("if (!" + std::string(n1) + ") goto " + lbl_cpy + ";");
            buffer_codigo.push_back("strcpy(" + t_concat + ", " + std::string(n1) + ");");
            buffer_codigo.push_back(lbl_cpy + ":");
            
            // Concatenação da segunda string
            std::string lbl_cat = novoLabel();
            buffer_codigo.push_back("if (!" + std::string(n2) + ") goto " + lbl_cat + ";");
            buffer_codigo.push_back("strcat(" + t_concat + ", " + std::string(n2) + ");");
            buffer_codigo.push_back(lbl_cat + ":");
            
            // Liberacao do buffer antigo e atualizacao
            buffer_codigo.push_back("free(" + std::string(n1) + ");");
            buffer_codigo.push_back(std::string(n1) + " = " + t_concat + ";");
            
            res.nome = copia_string(std::string(n1));
            res.tipo = 4;
            res.nome_orig = copia_string("");
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

static int visual_width(const std::string& str) {
    int len = 0;
    for (size_t i = 0; i < str.length(); ) {
        unsigned char c = str[i];
        if (c < 0x80) { i += 1; len += 1; }
        else if (c < 0xC0) { i += 1; }
        else if (c < 0xE0) { i += 2; len += 1; }
        else if (c < 0xF0) { i += 3; len += 1; }
        else { i += 4; len += 1; }
    }
    return len;
}

void yyerror(const char *s) {
    houve_erro = true;

    // ── Classifica o tipo de erro ─────────────────────────────────────────
    std::string msg(s);
    bool eh_lexico = (msg.find("Caractere inválido") != std::string::npos);
    bool eh_sintatico = (msg.find("syntax error") != std::string::npos || 
                         msg.find("unexpected") != std::string::npos);

    // ── Cabeçalho visual ──────────────────────────────────────────────────
    std::cerr << std::endl;
    std::cerr << COR_VERM  << "  ╔"; for(int i=0;i<46;i++) std::cerr<<"═"; std::cerr<<"╗" << COR_RESET << std::endl;

    std::string info_str;
    if (eh_lexico) {
        info_str = "  ⚠  ERRO LÉXICO — linha " + std::to_string(yylineno);
    } else if (eh_sintatico) {
        info_str = "  ⚠  ERRO SINTÁTICO — linha " + std::to_string(yylineno);
    } else {
        info_str = "  ✘  ERRO SEMÂNTICO — linha " + std::to_string(yylineno);
    }

    int spaces = 46 - visual_width(info_str);
    if (spaces < 0) spaces = 0;

    std::cerr << COR_VERM << "  ║" << COR_RESET
              << COR_NEGRITO << info_str << std::string(spaces, ' ')
              << COR_VERM << "║" << COR_RESET << std::endl;

    std::cerr << COR_VERM  << "  ╚"; for(int i=0;i<46;i++) std::cerr<<"═"; std::cerr<<"╝" << COR_RESET << std::endl;

    // ── Detalhe da mensagem ───────────────────────────────────────────────
    if (eh_sintatico) {
        // Remove o prefixo genérico "syntax error, " e exibe o resto
        std::string detalhe = msg;
        std::string prefixo = "syntax error, ";
        if (detalhe.substr(0, prefixo.size()) == prefixo)
            detalhe = detalhe.substr(prefixo.size());
        // Capitaliza primeira letra
        if (!detalhe.empty()) detalhe[0] = std::toupper((unsigned char)detalhe[0]);
        std::cerr << COR_AMAR  << "  Detalhe : " << COR_RESET << detalhe << std::endl;
    } else if (eh_lexico) {
        std::cerr << COR_AMAR  << "  Detalhe : " << COR_RESET << msg << std::endl;
    } else {
        // Erros semânticos: remove o prefixo "Erro Semantico: " para não repetir
        std::string detalhe = msg;
        std::string prefixo = "Erro Semantico: ";
        if (detalhe.substr(0, prefixo.size()) == prefixo)
            detalhe = detalhe.substr(prefixo.size());
        std::cerr << COR_AMAR  << "  Detalhe : " << COR_RESET << detalhe << std::endl;
    }

    std::cerr << COR_CIANO << "  Arquivo : " << COR_RESET;
    // Tenta mostrar o nome do arquivo (yyin pode não estar disponível aqui,
    // então usamos uma variável global auxiliar definida no main)
    extern std::string nome_arquivo_atual;
    if (!nome_arquivo_atual.empty())
        std::cerr << nome_arquivo_atual << std::endl;
    else
        std::cerr << "(stdin)" << std::endl;

    std::cerr << std::endl;
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

    // ─── nome_arquivo_atual: exposto para yyerror() exibir na mensagem de erro
    extern std::string nome_arquivo_atual;
    if (argc == 2) nome_arquivo_atual = std::string(argv[1]);

    yyparse();

    // ─── Guarda de erro: se qualquer erro ocorreu, não emite código C ────
    if (houve_erro) {
        return 1;
    }

    std::cout << "#include <stdio.h>\n";
    std::cout << "#include <string.h>\n";
    std::cout << "#include <stdlib.h>\n\n";

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