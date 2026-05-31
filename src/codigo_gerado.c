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
