/*
 * runtime.h  —  Runtime da linguagem Saphira / C--
 *
 * Este arquivo transforma o código C-- gerado pelo compilador Saphira
 * em código C válido, definindo as instruções built-in da linguagem:
 *
 *   write(expr)  →  imprime o valor na tela (tipo detectado automaticamente)
 *   read(var)    →  lê um valor do teclado para a variável
 *
 * Compatível com C11 (_Generic) e compilável com:
 *   gcc -std=c11 programa.c -o programa
 */

#ifndef SAPHIRA_RUNTIME_H
#define SAPHIRA_RUNTIME_H

#include <stdio.h>

/* ─── write(expr) ─────────────────────────────────────────────────────────
 * Detecta o tipo da expressão em tempo de compilação via _Generic (C11)
 * e escolhe o formato correto do printf automaticamente.
 * Suporta: int, float, double, char.
 */
#define write(x) printf(                          \
    _Generic((x),                                  \
        float:  "%f\n",                            \
        double: "%f\n",                            \
        char:   "%c\n",                            \
        default: "%d\n"                            \
    ), (x))

/* ─── read(var) ───────────────────────────────────────────────────────────
 * Lê um valor do stdin para a variável, detectando o tipo automaticamente.
 * Nota: para char usa " %c" para ignorar espaços/newlines pendentes.
 */
#define read(x) (_Generic(&(x),                   \
        float*:  scanf("%f",  &(x)),               \
        double*: scanf("%lf", &(x)),               \
        char*:   scanf(" %c", &(x)),               \
        default: scanf("%d",  &(x))))

#endif /* SAPHIRA_RUNTIME_H */
