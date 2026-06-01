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

// ─── Gerador de Labels (L1, L2, L3, ...) ──────────────────────────────────
static int contador_labels = 0;
std::string novoLabel() {
    return "L" + std::to_string(++contador_labels);
}

// ─── Contador de profundidade de laço (para validar break/continue) ────────
static int nivel_laco = 0;

// ─── Pilhas globais de labels (usadas pelas regras de fluxo de controle) ────
// Evitamos $<str>$ intermediários que corrompem o valor no Bison.
std::vector<std::string> pilha_labels_fim;   // Label de saída de if/while/for
std::vector<std::string> pilha_labels_ini;   // Label de início de while/for (retorno do goto)

// Buffer temporário para guardar o código de incremento do for
// (o incr_for é parseado antes do corpo, mas deve ser emitido depois)
std::vector<std::string> buffer_incr_for;

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

%token <str> ID NUM_INTEIRO NUM_REAL LITERAL_CHAR LITERAL_STRING
%token T_INT T_FLOAT T_BOOL T_CHAR T_STRING';'
%token SOM SUB MULT DIV ATRIB ABRE_PAR FECHA_PAR
%token MAIOR MENOR MAIOR_IGUAL MENOR_IGUAL IGUAL DIFERENTE E_LOGICO OU_LOGICO NEGACAO
%token TRUE FALSE
%token READ WRITE
%token IF ELSE WHILE FOR SWITCH CASE DEFAULT BREAK CONTINUE

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
%right NEGACAO
%left ABRE_PAR FECHA_PAR

%type <info> expressao
%type <str>  label_if label_while_inicio label_for_inicio

%%

programa: 
    | programa comando
    ;

comando: 
    T_INT ID ';' { 
          tabela.inserir(std::string($2), Tipo::INT); 
          buffer_codigo.push_back("int " + std::string($2) + ";"); // Gera o código C
      }
    | T_FLOAT ID ';' { 
          tabela.inserir(std::string($2), Tipo::FLOAT); 
          buffer_codigo.push_back("float " + std::string($2) + ";"); 
      }
    | T_BOOL ID ';'  { 
          tabela.inserir(std::string($2), Tipo::BOOL); 
          buffer_codigo.push_back("int " + std::string($2) + "; /* bool */"); 
      }
    | T_CHAR ID ';'  { 
          tabela.inserir(std::string($2), Tipo::CHAR); 
          buffer_codigo.push_back("char " + std::string($2) + ";"); 
      }
    | T_STRING ID ';' { 
            tabela.inserir(std::string($2), Tipo::STRING);
            buffer_codigo.push_back("string " + std::string($2) + ";");
        }
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
                buffer_codigo.push_back(t_conv + " = (float) " + std::string($3.nome) + ";");
                
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
    | READ ABRE_PAR ID FECHA_PAR ';' {
            std::string nome_str($3);
            if (!tabela.existe(nome_str)) {
                std::string msg = "Erro Semantico: Variavel '" + nome_str +
                                  "' nao declarada. Declare antes de usar em read().";
                yyerror(msg.c_str());
                exit(1);
            }
            // Gera instrução de leitura no código intermediário
            buffer_codigo.push_back("$read " + nome_str + ";$");
        }
    | WRITE ABRE_PAR expressao FECHA_PAR ';' {
            buffer_codigo.push_back("$write " + std::string($3.nome) + ";$");
        }
    | cmd_if
    | cmd_while
    | cmd_for
    | cmd_switch
    | BREAK ';' {
            // ── Verificação Semântica: break só é válido dentro de laço ──
            if (nivel_laco == 0) {
                yyerror("Erro Semantico: 'break' usado fora de um laco ou switch.");
                exit(1);
            }
            buffer_codigo.push_back("break;");
        }
    | CONTINUE ';' {
            // ── Verificação Semântica: continue só é válido dentro de laço ──
            if (nivel_laco == 0) {
                yyerror("Erro Semantico: 'continue' usado fora de um laco.");
                exit(1);
            }
            buffer_codigo.push_back("continue;");
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
        buffer_codigo.push_back("ifFalse " + std::string($2.nome) + " goto " + l_senao + ";");
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
        buffer_codigo.push_back("ifFalse " + std::string($4.nome) + " goto " + l_fim + ";");
        pilha_labels_fim.push_back(l_fim);
        nivel_laco++;
    } comando {
        nivel_laco--;
        std::string l_fim = pilha_labels_fim.back(); pilha_labels_fim.pop_back();
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
        buffer_codigo.push_back("ifFalse " + std::string($6.nome) + " goto " + l_fim + ";");
        pilha_labels_fim.push_back(l_fim);
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
        std::string l_fim = pilha_labels_fim.back(); pilha_labels_fim.pop_back();
        std::string l_ini = pilha_labels_ini.back(); pilha_labels_ini.pop_back();
        buffer_codigo.push_back("goto " + l_ini + ";");
        buffer_codigo.push_back(l_fim + ":");
    }
    ;

init_for:
      /* Vazio — for (;cond;incr) */
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
        if (tipo_destino == $3.tipo) {
            gera_codigo_atribuicao($1, $3.nome);
        } else if (tipo_destino == 1 && $3.tipo == 0) {
            std::string t_conv = gerador.novoTemporario();
            buffer_codigo.push_back(t_conv + " = (float) " + std::string($3.nome) + ";");
            gera_codigo_atribuicao($1, copia_string(t_conv));
        } else {
            std::string msg = "Erro Semantico: Tipos incompativeis na inicializacao do 'for'.";
            yyerror(msg.c_str());
            exit(1);
        }
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
        nivel_laco++;
    } lista_cases '}' {
        nivel_laco--;
        buffer_codigo.push_back("$L_switch_fim_" + std::to_string(contador_labels) + ":$");
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
    | LITERAL_STRING {
        $$.nome = copia_string(std::string($1));
        $$.tipo = 4; // STRING
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
        buffer_codigo.push_back(t_res + " = !" + std::string($2.nome) + ";");
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
            buffer_codigo.push_back("$" + t_res + " = " + std::string(n1) + " + " + std::string(n2) + ";$");
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
    std::cerr << s << std::endl;
}

int main() {
    yyparse();

    // Nenhum #include externo: o codigo intermediario é auto-contido.
    // bool é representado como int (0 = false, 1 = true) — o type check já foi feito.
    std::cout << "int main() {\n";
    
    // 1. Imprime os temporários declarados
    declarador.imprimirDeclaracoes(gerador.getTemporarios(), tabela);
    
    // 2. Imprime todo o código gerado indentado
    for (const std::string& linha : buffer_codigo) {
        std::cout << "    " << linha << "\n";
    }
    
    // 3. Finaliza o programa C
    std::cout << "    return 0;\n";
    std::cout << "}\n";

    return 0;
}