#include <stdio.h>
#include <string.h>

int main() {
    /* --- declaracoes de variaveis --- */
    int t1;
    int t2;
    int t3;
    int t4;
    int t5; /* bool */
    /* --- declaracoes de temporarios --- */
    int t6, t7, t8, t9;

    t1 = 0;
    t2 = 1;
    t4 = 0;
    printf("%d\n", t1);
    printf("%d\n", t2);
    t4 = 2;
    t6 = t4 < 10;
    t5 = t6;
    L1:
    if (!(t5)) goto L2;
    {
    t7 = t1 + t2;
    t3 = t7;
    printf("%d\n", t3);
    t1 = t2;
    t2 = t3;
    t8 = t4 + 1;
    t4 = t8;
    t9 = t4 < 10;
    t5 = t9;
    }
    goto L1;
    L2:
    return 0;
}
