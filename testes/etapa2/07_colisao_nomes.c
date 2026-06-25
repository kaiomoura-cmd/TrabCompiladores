#include <stdio.h>
#include <string.h>

int main() {
    /* --- declaracoes de variaveis --- */
    int t1;
    int t2;
    int t3;
    int t4;
    /* --- declaracoes de temporarios --- */
    int t5, t6;

    t1 = 100;
    t2 = 200;
    t3 = 300;
    t5 = t1 + t2;
    t6 = t5 + t3;
    t4 = t6;
    printf("%d\n", t1);
    printf("%d\n", t2);
    printf("%d\n", t3);
    printf("%d\n", t4);
    return 0;
}
