# Guia de Apresentação — Compilador C--

## 🎯 A Ideia Central (Abra com isso)

> *"Nós construímos um compilador do zero. Ele lê um código em uma linguagem que nós mesmos inventamos, verifica se ele faz sentido, e gera código intermediário pronto para ser executado."*

A linguagem se chama **C--** (C menos menos). Ela segue a **Filosofia Java/C#**: tipagem forte e segura. Diferente do C puro, que aceita qualquer mistura de tipos sem reclamar, o nosso compilador **rejeita** código que não faz sentido e aborta com uma mensagem de erro clara.

---

## 🏗️ A Arquitetura — O que construímos

Explique que um compilador tem fases. O nosso tem três:

```
Código .cmm  →  [Analisador Léxico]  →  [Analisador Sintático + Semântico]  →  Código Intermediário
   (texto)         lexico.l (Flex)         sintatico.y (Bison)                    (saída no terminal)
```

### 1. Analisador Léxico — `lexico.l`
> *"É o compilador lendo o código letra por letra e transformando em peças com significado."*

- Pega o texto bruto e transforma em **tokens**: `int`, `=`, `5`, `;`, `if`, `while`...
- Exemplo: `if (x > 5)` vira os tokens: `IF`, `ABRE_PAR`, `ID("x")`, `MAIOR`, `NUM_INTEIRO("5")`, `FECHA_PAR`

### 2. Analisador Sintático — `sintatico.y`
> *"É o compilador verificando se a gramática está correta — como verificar se uma frase em português tem sujeito, verbo e predicado."*

- Usa a gramática da linguagem para verificar se a sequência de tokens faz sentido estruturalmente
- Gerado pela ferramenta **Bison**

### 3. Analisador Semântico — (dentro do `sintatico.y`)
> *"É o compilador verificando se o significado faz sentido — não adianta a frase estar gramaticalmente correta se ela é uma bobagem."*

- Verifica tipos, variáveis declaradas, uso correto de `break`/`continue`, etc.
- **Aqui vive a nossa filosofia estrita**

---

## 🧱 Os Módulos de Suporte

### Tabela de Símbolos — `simbolos.cpp`
> *"É a memória do compilador. Toda vez que declaramos uma variável, ela é guardada aqui com seu nome e tipo."*

- Implementada como uma **pilha de escopos**: cada `{ }` cria um novo nível
- Quando saímos de um `{ }`, as variáveis daquele bloco somem automaticamente — **vazamento de escopo não existe**

```
Escopo 0 (global): int i, bool rodando
Escopo 1 (dentro do while): int par, int fim
```

### Gerador de Temporários — `temporarios.cpp`
> *"Quando o compilador precisa guardar um resultado intermediário de uma conta, ele cria uma variável temporária automaticamente: T1, T2, T3..."*

- Exemplo: `nota > 5` precisa de um lugar para guardar o resultado antes de atribuir a `aprovado`
- O compilador gera: `T1 = nota > 5; aprovado = T1;`

---

## ⚙️ A Filosofia em Prática — Mostre os exemplos

### ✅ Código válido (aceito)
```java
bool aprovado;
int nota;

nota = 7;
aprovado = nota > 5;  // nota > 5 é uma expressão bool: OK

if (aprovado) {       // aprovado é bool: OK
    nota = 10;
}
```
**Código intermediário gerado:**
```
int aprovado; /* bool */
int nota;
T1 = nota > 5;
aprovado = T1;
ifFalse aprovado goto L1;
{
  nota = 10;
}
L1:
```

---

### ❌ Código inválido (rejeitado)
```java
int x;
x = 5;
if (x) { ... }  // x é int, não bool!
```
**Saída do compilador:**
```
Erro Semantico: A condicao do 'if' deve ser do tipo bool.
```

> *"Em C isso compilaria e funcionaria. No nosso compilador, isso é um erro — porque misturar tipos é uma inconsistência semântica."*

---

## 🔁 Geração de Código — Como os saltos funcionam

Este é o coração técnico. Explique a estratégia de **labels e gotos**:

### `if / else`
```
ifFalse <condição> goto L_else;
  <bloco then>
goto L_fim;
L_else:
  <bloco else>
L_fim:
```

### `while`
```
L_inicio:
ifFalse <condição> goto L_fim;
  <corpo>
goto L_inicio;
L_fim:
```

### `for`
```
<init>
L_inicio:
ifFalse <condição> goto L_fim;
  <corpo>
  <incremento>   ← emitido depois do corpo (não antes!)
goto L_inicio;
L_fim:
```

> *"O for foi o mais desafiador: no Bison, o incremento é parseado antes do corpo, mas precisa ser executado depois. Resolvemos isso com um buffer temporário que segura o código do incremento e o emite na posição correta."*

---

## 🛡️ Validações Semânticas Implementadas

| Situação | Comportamento |
|---|---|
| `if (int)` | ❌ Erro: condição deve ser bool |
| `while (float)` | ❌ Erro: condição deve ser bool |
| `for (...; int; ...)` | ❌ Erro: condição deve ser bool |
| `break` fora de laço | ❌ Erro: break fora de laço/switch |
| `continue` fora de laço | ❌ Erro: continue fora de laço |
| Variável não declarada | ❌ Erro: variável não declarada |
| Redeclaração no mesmo escopo | ❌ Erro: já declarada |
| `int` atribuído a `bool` | ❌ Erro: tipos incompatíveis |
| `int` atribuído a `float` | ✅ Coerção segura automática (widening) |

---

## 📦 O Código Intermediário — A Decisão de Design

> *"O código que geramos é auto-contido. Ele não usa nenhuma biblioteca externa além de strcpy e strcat."*

**Por quê isso importa?**
- Usar `#include <stdio.h>` seria delegar trabalho para o GCC — estaríamos empurrando o problema pra frente
- Nós somos os donos da semântica. O `bool` que o usuário escreve vira `int` no código de saída porque já verificamos tudo antes. É o mesmo que Java faz: o código-fonte tem tipos ricos, o bytecode é mais simples

```c
// Antes (errado): dependia do GCC para entender bool
#include <stdbool.h>
bool aprovado;

// Agora (correto): auto-contido, sem bibliotecas externas
int aprovado; /* bool */
```

---

## 💡 Possíveis perguntas e respostas

**"Por que vocês usaram Flex e Bison e não fizeram tudo na mão?"**
> Flex e Bison são ferramentas clássicas de compiladores, usadas em produção (o compilador do GCC usa técnicas similares). Elas geram automaticamente o analisador léxico e o parser a partir de regras declarativas — nos permitindo focar na semântica e na geração de código.

**"O que são temporários?"**
> São variáveis criadas pelo compilador, não pelo programador. Toda expressão composta precisa de um lugar temporário para guardar resultados intermediários antes de usá-los.

**"Por que `break` e `continue` precisam de verificação especial?"**
> Porque semanticamente eles só fazem sentido dentro de um laço. Um `break` no topo do programa não tem para onde saltar — seria um erro de lógica. Controlamos isso com um contador (`nivel_laco`) que incrementa ao entrar em um laço e decrementa ao sair.

**"O que é o `ifFalse ... goto`?"**
> É a representação de código de três endereços — o padrão clássico de código intermediário descrito no livro "Compiladores: Princípios, Técnicas e Ferramentas" (o Livro do Dragão). É a forma mais simples de representar desvios condicionais antes de gerar código de máquina.
