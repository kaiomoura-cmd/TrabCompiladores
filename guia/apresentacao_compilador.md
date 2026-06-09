# Manual de Especificação & Documentação da Linguagem Saphira (C--)

Este documento serve como a documentação oficial da linguagem **Saphira** (também referenciada como **C--**). Ele descreve a especificação da linguagem, as regras de tipagem, a arquitetura do compilador, a geração de código intermediário e o guia completo de comandos de terminal para compilar e executar programas.

---

## 1. Visão Geral & Filosofia

A linguagem **Saphira** é uma linguagem de programação imperativa fortemente tipada, projetada com foco em segurança de tipos. Ela adota a **filosofia Java/C#**: ao contrário de C puro, que permite conversões implícitas arriscadas (como tratar inteiros como booleanos ou truncar floats silenciosamente), o compilador Saphira realiza análises semânticas rígidas e **rejeita em tempo de compilação** quaisquer operações que violem a segurança de tipos.

### Características Principais
* **Tipagem Estrita:** Verificação estrita de compatibilidade em atribuições e operações.
* **Escopo de Variáveis Dinâmico:** Gerenciamento por blocos `{ }` e escopos de parâmetros de funções. Vazamento de escopo é proibido.
* **Funções e Escopos Isolados:** Definição de funções com reinicialização do gerador de temporários para cada escopo.
* **Estruturas de Dados Bidimensionais:** Suporte nativo a vetores e matrizes bidimensionais (2D).
* **Código Intermediário Autocontido:** O compilador traduz o código Saphira diretamente para código C nativo e válido, sem depender de pós-processamento por expressões regulares ou macros externas.

---

## 2. Sistema de Tipos e Operações

Saphira suporta os seguintes tipos primitivos e estruturas complexas:

| Tipo Saphira | Representação Interna em C | Descrição |
| :--- | :--- | :--- |
| `int` | `int` | Inteiros padrão de 32 bits. |
| `float` | `float` | Números de ponto flutuante. |
| `bool` | `int` (0 ou 1) | Valores lógicos (`true` e `false`). |
| `char` | `char` | Caractere único delimitado por aspas simples (ex: `'A'`). |
| `string` | `char[256]` | Cadeia de caracteres (máx. 256 bytes) delimitada por aspas duplas (ex: `"Olá"`). |
| `enum` | `int` | Definição de enums mapeados para constantes do tipo `int`. |

### 2.1. Regras de Atribuição e Coerção
* **Atribuição Direta:** Só é permitida entre tipos exatamente idênticos.
* **Coerção Segura (Widening):** É permitido atribuir um valor `int` a uma variável `float`. O compilador gera automaticamente a promoção de tipo `(float)` no código intermediário.
* **Casting Explícito:** É possível forçar conversões através de casts explícitos:
  * `(int) expressao_float` (converte float para int)
  * `(float) expressao_int` (converte int para float)
* **Tipos Proibidos:** Atribuir `float` a `int`, `int` a `bool`, ou qualquer mistura com `char` e `string` sem as funções adequadas gera um **Erro Semântico** que aborta a compilação.

### 2.2. Vetores e Matrizes
* **Declaração e Acesso:** Suporte a vetores (1D) e matrizes (2D) indexados por inteiros.
  ```java
  int v[5];
  int m[2][3];
  v[0] = 10;
  m[0][1] = v[0];
  ```
* **Inicialização com Listas:**
  ```java
  int v[5] = {10, 20, 30, 40, 50};
  int m[2][3] = {{1, 2, 3}, {4, 5, 6}};
  ```

### 2.3. Slices (Fatiamento de Vetores)
* Slices permitem fatiar um vetor e atribuir o pedaço a outro vetor ou imprimi-lo diretamente.
  ```java
  int v[5] = {10, 20, 30, 40, 50};
  int dest[3];
  dest = v[1:4]; // Copia v[1..3] (20, 30, 40) para dest[0..2]
  write(v[1:4]); // Imprime "[20, 30, 40]" no terminal
  ```

### 2.4. Enumerações (Enums)
* Declaradas no nível global e associadas a constantes auto-incrementadas iniciando em 0.
  ```java
  enum Estado { OFF, ON };
  Estado est = ON;
  ```

---

## 3. Estruturas de Controle de Fluxo & Funções

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
* O `for` suporta declarações inline opcionais em seu bloco de inicialização.
```java
for (int i = 1; i <= 10; i = i + 1) {
    write(i);
}
```

### 3.3. Controle de Loops (`break` e `continue`)
* O compilador gerencia pilhas de desvio exclusivas para cada laço.
* O comando `break` aborta o laço mais interno ativo ou sai de um bloco `switch`.
* O comando `continue` salta para a próxima iteração.
* Usar `break` ou `continue` fora de um contexto válido de laço gera um erro semântico imediato.

### 3.4. Seleção Múltipla (`switch` / `case` / `default`)
Permite múltiplos desvios baseados em uma expressão inteira ou caractere.
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

### 3.5. Funções
* Suporta retorno tipado e procedimentos do tipo `void`.
* Escopos locais isolados (o gerador de temporários reseta a contagem ao entrar na função).
```java
int duplicar(int x) {
    int res = x * 2;
    return res;
}

void print_status(int st) {
    if (st == 1) {
        write("Estado: LIGADO");
    } else {
        write("Estado: DESLIGADO");
    }
}
```

---

## 4. Entrada e Saída (I/O)

Saphira possui duas instruções primitivas para interação com o terminal:

1. **`write(expressao)`**: Imprime o valor da expressão no terminal seguido de uma quebra de linha. O compilador detecta o tipo da expressão em tempo de compilação e seleciona automaticamente o formato adequado para o `printf` (`%d\n`, `%f\n`, `%c\n`, `%s\n`). Também suporta exibição formatada de slices de vetores.
2. **`read(variavel)`**: Lê um valor digitado no teclado e armazena na variável fornecida. O compilador gera a chamada do `scanf` com a formatação adequada para o tipo da variável (`%d`, `%f`, `%c`, `%s`). No caso do tipo `char`, ele insere automaticamente um espaço em branco antes do formatador (`" %c"`) para limpar newlines pendentes no buffer de entrada.

---

## 5. Arquitetura do Compilador

O compilador Saphira é estruturado em fases de processamento:

```
Arquivo .saphira ➔ [Lexer (Flex)] ➔ [Parser & Semântico (Bison)] ➔ Código C Nativo (saída)
```

1. **Analisador Léxico (`src/lexico.l`):** Varre o arquivo-fonte caractere por caractere, ignorando espaços e comentários, e agrupa os caracteres em tokens reconhecidos.
2. **Analisador Sintático (`src/sintatico.y`):** Monta a estrutura gramatical a partir dos tokens usando regras geradas pelo Bison.
3. **Analisador Semântico:** Inserido diretamente nas regras de redução do parser. Ele realiza o type checking, valida declarações, gerencia o escopo de variáveis e controla a profundidade de laços.
4. **Tabela de Símbolos (`src/simbolos.cpp`):** Gerencia variáveis ativas usando uma pilha de escopos (estruturada como vetores de hashes). Cada bloco `{ }` empilha um escopo transparente, que é removido (limpando as variáveis locais) ao encontrar o caractere `}` correspondente.
5. **Gerador de Temporários (`src/temporarios.cpp`):** Cria variáveis auxiliares (`t1`, `t2`, `t3`...) para armazenar resultados de expressões intermediárias. Evita colisões de nomes verificando se o temporário gerado já foi declarado pelo usuário.
6. **Buffers do compilador:** Separadores específicos para Enums, Funções e Código Principal (`main()`), permitindo reagrupar o arquivo em C final de forma sequencialmente válida.

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

# Compilar o compilador (gera o binário em bin/compilador)
make
```

### 6.3. Compilando um Programa Saphira para C
Você pode chamar o compilador diretamente passando o arquivo-fonte. A saída gerada será o código C equivalente impresso no terminal:
```bash
# Executa e exibe o código C gerado na tela:
./bin/compilador testes/13_etapa3.saphira

# Salva o código C gerado em um arquivo de saída:
./bin/compilador testes/13_etapa3.saphira > saida.c
```

### 6.4. Compilando o Código C Gerado via GCC
Uma vez gerado o código C, ele pode ser compilado com qualquer compilador C padrão (como GCC) diretamente:
```bash
# Compila o arquivo C intermediário para um binário executável:
gcc -std=c11 saida.c -o programa

# Executa o programa compilado:
./programa
```

### 6.5. Usando o Script Auxiliar de Execução (`executar.sh`)
Para facilitar o desenvolvimento, você pode utilizar o script `executar.sh`, que automatiza todo o pipeline (Compilação Saphira ➔ C ➔ Executável GCC ➔ Execução):

```bash
# Compilar e executar um arquivo específico:
./executar.sh testes/13_etapa3.saphira

# Compilar e executar exibindo também o código C gerado no terminal:
./executar.sh testes/13_etapa3.saphira --ver

# Executar a suíte completa de testes automatizados:
./executar.sh --todos
```
