#include <stdio.h>
#include <string.h>

int main() {
    /* --- declaracoes de variaveis --- */
    int t1;
    int t2;
    int t3;
    int t4;
    int t5;
    int t6;
    /* --- declaracoes de temporarios --- */
    int t7, t8, t9, t10;

    t1 = 10;
    t2 = 3;
    t7 = t1 + t2;
    t3 = t7;
    t8 = t1 - t2;
    t4 = t8;
    t9 = t1 * t2;
    t5 = t9;
    t10 = t1 / t2;
    t6 = t10;
    printf("%d\n", t3);
    printf("%d\n", t4);
    printf("%d\n", t5);
    printf("%d\n", t6);
    return 0;
}
