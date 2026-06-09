	# Manual de Especificação & Documentação da Linguagem Saphira (C--)

Este documento serve como a documentação oficial da linguagem **Saphira** (também referenciada como **C--**). Ele descreve a especificação da linguagem, as regras de tipagem, a arquitetura do compilador, a geração de código intermediário e o guia completo de comandos de terminal para compilar e executar programas.

---

## 1. Visão Geral & Filosofia

A linguagem **Saphira** é uma linguagem de programação imperativa fortemente tipada, projetada com foco em segurança de tipos. Ela adota a **filosofia Java/C#**: ao contrário de C puro, que permite conversões implícitas arriscadas (como tratar inteiros como booleanos ou truncar floats silenciosamente), o compilador Saphira realiza análises semânticas rígidas e **rejeita em tempo de compilação** quaisquer operações que violem a segurança de tipos.

### Características Principais
* **Tipagem Estrita:** Verificação estrita de compatibilidade em atribuições e operações.
* **Escopo de Variáveis Dinâmico:** Gerenciamento por blocos `{ }`. Vazamento de escopo é proibido.
* **Código Intermediário Autocontido:** O compilador traduz o código Saphira diretamente para código C nativo e válido, sem depender de pós-processamento por expressões regulares ou macros externas.

---

## 2. Sistema de Tipos e Operações

Saphira suporta os seguintes tipos primitivos:

| Tipo Saphira | Representação Interna em C | Descrição |
| :--- | :--- | :--- |
| `int` | `int` | Inteiros padrão de 32 bits. |
| `float` | `float` | Números de ponto flutuante. |
| `bool` | `int` (0 ou 1) | Valores lógicos (`true` e `false`). |
| `char` | `char` | Caractere único delimitado por aspas simples (ex: `'A'`). |
| `string` | `char[256]` | Cadeia de caracteres (máx. 256 bytes) delimitada por aspas duplas (ex: `"Olá"`). |

### 2.1. Regras de Atribuição e Coerção
* **Atribuição Direta:** Só é permitida entre tipos exatamente idênticos.
* **Coerção Segura (Widening):** É permitido atribuir um valor `int` a uma variável `float`. O compilador gera automaticamente a promoção de tipo `(float)` no código intermediário.
* **Casting Explícito:** É possível forçar conversões através de casts explícitos:
  * `(int) expressao_float` (converte float para int)
  * `(float) expressao_int` (converte int para float)
* **Tipos Proibidos:** Atribuir `float` a `int`, `int` a `bool`, ou qualquer mistura com `char` e `string` sem as funções adequadas gera um **Erro Semântico** que aborta a compilação.

### 2.2. Operações por Tipo
* **Aritméticas (`+`, `-`, `*`, `/`):** Suportadas por `int` e `float`. O operador `/` realiza divisão inteira se ambos os operandos forem `int`, e divisão de ponto flutuante se houver `float`.
* **Relacionais (`>`, `>=`, `<`, `<=`, `==`, `!=`):** Comparam expressões aritméticas e retornam um valor `bool` (`0` ou `1`).
* **Lógicas (`&&`, `||`, `!`):** Operam exclusivamente sobre valores do tipo `bool`.
* **Strings:**
  * **Atribuição:** A atribuição `s = "texto"` ou `s1 = s2` é traduzida pelo compilador usando a função C `strcpy`.
  * **Concatenação (`+`):** Somar duas strings (`s1 + s2`) realiza a concatenação delas, sendo traduzido diretamente para `strcat` no C gerado.

---

## 3. Estruturas de Controle de Fluxo

### 3.1. Condicional (`if` / `else`)
A condição avaliada no `if` deve obrigatoriamente ser do tipo `bool`.
```java
if (ativo) {
    write(1);
} else {
    write(0);
}
```

### 3.2. Laços de Repetição (`while` e `for`)
* A condição de parada dos laços deve ser do tipo `bool`.
* O `for` suporta declarações inline opcionais em seu bloco de inicialização (ex: `for (int i = 1; ...)`).
```java
for (int i = 1; i <= 10; i = i + 1) {
    write(i);
}
```

### 3.3. Controle de Loops (`break` e `continue`)
* O compilador gerencia pilhas de desvio exclusivas para cada laço.
* O comando `break` aborta o laço mais interno ativo ou sai de um bloco `switch`.
* O comando `continue` salta para a próxima iteração (retorno da condição no `while` ou bloco de incremento no `for`).
* Usar `break` ou `continue` fora de um contexto válido de laço gera um erro semântico imediato.

### 3.4. Seleção Múltipla (`switch` / `case` / `default`)
Permite múltiplos desvios condicionais baseados em uma expressão inteira ou caractere.
```java
switch (opcao) {
    case 1: {
        write('A');
        break;
    }
    default: {
        write('Z');
    }
}
```

---

## 4. Entrada e Saída (I/O)

Saphira possui duas instruções primitivas para interação com o terminal:

1. **`write(expressao)`**: Imprime o valor da expressão no terminal seguido de uma quebra de linha. O compilador detecta o tipo da expressão em tempo de compilação e seleciona automaticamente o formato adequado para o `printf` (`%d\n`, `%f\n`, `%c\n`, `%s\n`).
2. **`read(variavel)`**: Lê um valor digitado no teclado e armazena na variável fornecida. O compilador gera a chamada do `scanf` com a formatação adequada para o tipo da variável (`%d`, `%f`, `%c`, `%s`). No caso do tipo `char`, ele insere automaticamente um espaço em branco antes do formatador (`" %c"`) para limpar newlines pendentes no buffer de entrada.

---

## 5. Arquitetura do Compilador

O compilador Saphira é estruturado em fases de processamento:

```
Arquivo .saphira ➔ [Lexer (Flex)] ➔ [Parser & Semântico (Bison)] ➔ Código C Nativo (saída)
```

1. **Analisador Léxico (`src/lexico.l`):** Varre o arquivo-fonte caractere por caractere, ignorando espaços e comentários, e agrupa os caracteres em tokens reconhecidos (palavras-chave, operadores, literais e identificadores).
2. **Analisador Sintático (`src/sintatico.y`):** Monta a estrutura gramatical a partir dos tokens usando regras geradas pelo Bison.
3. **Analisador Semântico:** Inserido diretamente nas regras de redução do parser. Ele realiza o type checking, valida declarações, gerencia o escopo de variáveis e controla a profundidade de laços para validação de `break`/`continue`.
4. **Tabela de Símbolos (`src/simbolos.cpp`):** Gerencia variáveis ativas usando uma pilha de escopos (estruturada como vetores de hashes). Cada bloco `{ }` empilha um escopo transparente, que é removido (limpando as variáveis locais) ao encontrar o caractere `}` correspondente.
5. **Gerador de Temporários (`src/temporarios.cpp`):** Cria variáveis auxiliares (`t1`, `t2`, `t3`...) para armazenar resultados de expressões intermediárias. Evita colisões de nomes verificando se o temporário gerado já foi declarado pelo usuário.

---

## 6. Guia de Execução no Terminal

Esta seção descreve os comandos para construir o compilador, gerar o código intermediário e executar os programas.

### 6.1. Requisitos de Ambiente
* Compilador GCC (compatível com C++17 e C11).
* Ferramentas `make`, `flex` (v2.6+) e `bison` (v3.0+).

### 6.2. Construindo o Compilador
Para compilar o código fonte do compilador Saphira:
```bash
# Limpar arquivos de compilações anteriores
make clean
# Exemplo de saída: rm -f src/*.tab.* src/lex.yy.c bin/compilador /tmp/saphira_*

# Compilar o compilador (gera o binário em bin/compilador)
make
# Exemplo de saída:
# bison -d src/sintatico.y -o src/sintatico.tab.c
# flex -o src/lex.yy.c src/lexico.l
# g++ -std=c++17 -Wall -I src ... -o bin/compilador
```

### 6.3. Compilando um Programa Saphira para C
Você pode chamar o compilador diretamente passando o arquivo-fonte. A saída gerada será o código C equivalente impresso no terminal (pode ser redirecionado para um arquivo):
```bash
# Executa e exibe o código C gerado na tela:
./bin/compilador testes/01_basico.saphira

# Exemplo de saída no terminal (trecho):
# #include <stdio.h>
# #include <string.h>
# int main() {
#     int a; int b; int soma; ...
#     int t1, t2, t3, t4;
#     a = 10; b = 3;
#     t1 = a + b; soma = t1;
#     printf("%d\n", soma);
#     ...
#     return 0;
# }

# Salva o código C gerado em um arquivo de saída:
./bin/compilador testes/01_basico.saphira > saida.c
```

### 6.4. Compilando o Código C Gerado via GCC
Uma vez gerado o código C, ele pode ser compilado com qualquer compilador C padrão (como GCC) diretamente:
```bash
# Compila o arquivo C intermediário para um binário executável:
gcc -std=c11 saida.c -o programa

# Executa o programa compilado:
./programa
# Exemplo de saída no terminal:
# 13
# 7
# 30
# 3
```

### 6.5. Usando o Script Auxiliar de Execução (`executar.sh`)
Para facilitar o desenvolvimento, você pode utilizar o script `executar.sh`, que automatiza todo o pipeline (Compilação Saphira ➔ C ➔ Executável GCC ➔ Execução):

```bash
# Compilar e executar um arquivo específico:
./executar.sh testes/01_basico.saphira
# Exemplo de saída:
# [1/3] Compilando Saphira → C-- ...
# [2/3] Copiando código C gerado ...
# [3/3] Compilando C → executável (gcc) ...
#
# ── Saída do programa ────────────────────────────
# 13
# 7
# 30
# 3
# ─────────────────────────────────────────────────

# Compilar e executar exibindo também o código C gerado no terminal:
./executar.sh testes/01_basico.saphira --ver
# Exemplo de saída:
# Exibe o código C gerado antes de mostrar o bloco de execução "── Saída do programa ──".

# Executar a suíte completa de testes automatizados:
./executar.sh --todos
# Exemplo de saída:
# Rodando todos os testes em testes/ ...
# ...
# Resultado: 9 passou(aram)  0 falhou(aram)
```
