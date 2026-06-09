# Compilador FOCA

O FOCA é o início do desenvolvimento de um compilador demonstrado na disciplina de Compiladores.

## Instalação

É necessário as ferramentas `flex`, `bison` e `g++`.

### Ubuntu
```console
sudo apt install build-essential flex bison
```

## Execução

```console
make                                        # compila o compilador
make run FILE=exemplos/01_soma.foca         # roda um exemplo
make test                                   # roda todos os testes
make test-01                                # testa a etapa 01
make verify FILE=exemplos/03_declaracao_temp.foca  # compila e executa o C gerado
make clean                                  # limpa arquivos gerados
```

## Vídeos

1. Flex: https://youtu.be/c9WLbVZ5T3w
2. Bison: https://youtu.be/ATW-mq0ahaA
3. Código Intermediário: https://youtu.be/xLqb5RqXANQ
4. Vídeo com a construção desse código: https://youtu.be/FmR3p1-tzoc

Materiais sobre a disciplina de compiladores: http://filipe.braida.com.br/pages/courses/compiladores/

---

## Roadmap

O compilador é desenvolvido em etapas progressivas. Cada etapa tem um exemplo em `exemplos/` com a entrada (`.foca`) e a saída esperada (`.expected`). Use `make test-NN` para verificar se sua implementação está correta.

---

### #1 Expressão com Soma

Fazer a soma sobre inteiros funcionar.

**Código na LP:**
```
1 + 2 + 3
```

**Código Intermediário:**
```c
t1 = 1;
t2 = 2;
t3 = t1 + t2;
t4 = 3;
t5 = t3 + t4;
```

**Teste:** `make test-01`

---

### #2 Expressão com os Demais Operadores Aritméticos

Fazer as demais operações aritméticas sobre inteiros funcionarem.

**Código na LP:**
```
1 + 2 * 3
```

**Código Intermediário:**
```c
t1 = 1;
t2 = 2;
t3 = 3;
t4 = t2 * t3;
t5 = t1 + t4;
```

**Teste:** `make test-02`

---

### #3 Declaração das Cédulas de Memória Usadas

Deverá declarar antes do código todas as cédulas de memória utilizadas.

**Código na LP:**
```
1 + 2 * 3
```

**Código Intermediário:**
```c
int t1;
int t2;
int t3;
int t4;
int t5;

t1 = 1;
t2 = 2;
t3 = 3;
t4 = t2 * t3;
t5 = t1 + t4;
```

> **OBS:** Nesse momento, já é possível compilar esse código em C. A principal dificuldade passa a ser a necessidade de impressão do resultado para verificar se a conta está correta.

**Teste:** `make test-03`

---

### #4 Desenvolvimento do Parênteses

Deverá permitir o uso de parênteses nas expressões.

**Código na LP:**
```
(1 + 2) * 3
```

**Código Intermediário:**
```c
int t1;
int t2;
int t3;
int t4;
int t5;

t1 = 1;
t2 = 2;
t3 = t1 + t2;
t4 = 3;
t5 = t3 * t4;
```

**Teste:** `make test-04`

---

### #5 Atribuição

Deverá permitir a atribuição a uma variável e sua utilização em expressões.

**Código na LP:**
```
A = (A + 2) * 3
```

**Código Intermediário:**
```c
int t1;
int t2;
int t3;
int t4;
int t5;

t1 = A;
t2 = 2;
t3 = t1 + t2;
t4 = 3;
t5 = t3 * t4;
A = t5;
```

> **OBS:** Esse código volta a ter problemas de compilação, pois ainda não resolvemos a alocação da variável no código intermediário.

**Teste:** `make test-05`

---

### #6 Declaração

Deverá criar uma tabela de símbolos para representar as cédulas de memória alocadas pelo usuário. Esse é um exemplo de declaração explícita, mas outras variações de design são possíveis.

**Código na LP:**
```
int A;
A = (A + 2) * 3
```

**Código Intermediário:**
```c
int t1;
int t2;
int t3;
int t4;
int t5;

t2 = 2;
t3 = t1 + t2;
t4 = 3;
t5 = t3 * t4;
t1 = t5;
```

> **OBS:** É possível adicionar comentários ao código gerado para facilitar a depuração.

**Teste:** `make test-06`

---

### #7 Tipo Float

Deverá ser possível utilizar o tipo `float`. Para isso, será necessário alterar a tabela de símbolos para armazenar o tipo da variável. Além disso, será preciso carregar o tipo resultante entre os nós da expressão.

**Código na LP:**
```
int A;
A = (A + 2) * 3.0
```

**Código Intermediário:**
```c
int t1;
int t2;
int t3;
float t4;
int t5;

t2 = 2;
t3 = t1 + t2;
t4 = 3.0;
t5 = t4 * t3;
t1 = t5;
```

**Teste:** `make test-07`

---

### #8 Tipos char e boolean

Deverá ser possível declarar e utilizar variáveis dos tipos `char` e `boolean`.

**Código na LP:**
```
char C;
C = 'a';

bool B;
B = true;
```

**Código Intermediário:**
```c
char t1;
int t2;

t1 = 'a';
t2 = 1;
```

> **OBS:** Lembrando que não existe tipo `bool` no código intermediário. Contudo, macros podem ser usadas para melhorar a legibilidade do código.

**Teste:** `make test-08`

---

### #9 Operadores Relacionais

Permitir expressões com operadores relacionais (`<`, `<=`, `>`, `>=`, `==`, `!=`). O resultado da operação deve ser tratado como valor lógico.

**Código na LP:**
```
bool R;
R = 3 < 5;
```

**Código Intermediário:**
```c
int t1;
int t2;
int t3;
int t4;

t1 = 3;
t2 = 5;
t3 = t1 < t2;
t4 = t3;
```

**Teste:** `make test-09`

---

### #10 Operadores Lógicos

Implementar os operadores lógicos `&&`, `||` e `!`. Deve-se verificar a compatibilidade de tipos nas expressões lógicas.

**Código na LP:**
```
bool B1;
bool B2;
bool R;
R = B1 && !B2;
```

**Código Intermediário:**
```c
int t1;
int t2;
int t3;
int t4;
int t5;

t2 = !t1;
t4 = t3 && t2;
t5 = t4;
```

**Teste:** `make test-10`

---

### #11 Conversão Implícita

Deverá ocorrer a conversão automática de `int` para `float` em expressões mistas. Essa conversão deve ser aplicada na geração do código intermediário. Será necessário criar uma tabela de conversão para determinar os tipos resultantes. Estratégias como as usadas em Ada não serão aceitas.

**Código na LP:**
```
float F;
int I;
F = I + 2.5;
```

**Código Intermediário:**
```c
int t1;
float t2;
float t3;
float t4;
float t5;

t2 = (float) t1;
t3 = 2.5;
t4 = t2 + t3;
t5 = t4;
```

> **OBS:** A conversão pode ser validada na análise semântica para evitar operações inválidas.

**Teste:** `make test-11`

---

### #12 Conversão Explícita

Permitir expressões com casting explícito. A conversão deverá ser aplicada diretamente no código intermediário.

**Código na LP:**
```
int I;
float F;
I = (int) F;
```

**Código Intermediário:**
```c
float t1;
float t2;
int t3;
int t4;

t2 = t1;
t3 = (int) t2;
t4 = t3;
```

> **OBS:** O cast explícito pode ser validado na análise semântica para evitar conversões inválidas.

**Teste:** `make test-12`
