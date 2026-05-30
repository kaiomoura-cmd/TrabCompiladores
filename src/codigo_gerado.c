'a' Escopo Nivel 0
'b' Escopo Nivel 1
'c' Escopo Nivel 2
'c' Escopo Nivel 2
'b' Escopo Nivel 1
'b' Escopo Nivel 1
'a' Escopo Nivel 0
#include <stdio.h>
#include <stdbool.h> // Para o gcc entender booleanos

int main() {
    int a;
    a = 1;
    {
    int b;
    b = 2;
    {
    int c;
    c = 3;
    b = c;
    a = b;
    }
    }
    return 0;
}
