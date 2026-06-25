#include <stdio.h>
#include <string.h>

int main() {
    /* --- declaracoes de variaveis --- */
    int t1;
    int t2;
    int t6;
    int t7;
    int t10;
    /* --- declaracoes de temporarios --- */
    int t3, t4, t5, t8, t9, t11, t12;

    t1 = 1;
    t2 = 1;
    L1:
    t3 = t2 <= 5;
    if (!(t3)) goto L2;
    t4 = t2 + 1;
    {
    t5 = t1 * t2;
    t1 = t5;
    }
    t2 = t4;
    goto L1;
    L2:
    printf("%d\n", t1);
    t6 = 0;
    t7 = 1;
    L3:
    t8 = t7 <= 4;
    if (!(t8)) goto L4;
    t9 = t7 + 1;
    {
    t11 = t7 * t7;
    t10 = t11;
    t12 = t6 + t10;
    t6 = t12;
    }
    t7 = t9;
    goto L3;
    L4:
    printf("%d\n", t6);
    return 0;
}
