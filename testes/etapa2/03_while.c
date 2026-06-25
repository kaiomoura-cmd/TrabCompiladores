#include <stdio.h>
#include <string.h>

int main() {
    /* --- declaracoes de variaveis --- */
    int t1;
    int t2;
    int t3; /* bool */
    int t5; /* bool */
    int t10;
    int t11; /* bool */
    int t13;
    /* --- declaracoes de temporarios --- */
    int t4, t6, t7, t8, t9, t12, t14, t15, t16;

    t1 = 1;
    t2 = 0;
    t4 = t1 <= 10;
    t3 = t4;
    L1:
    if (!(t3)) goto L2;
    {
    t6 = t1 == 6;
    t5 = t6;
    if (!(t5)) goto L3;
    {
    goto L2;
    }
    L3:
    t7 = t2 + t1;
    t2 = t7;
    t8 = t1 + 1;
    t1 = t8;
    t9 = t1 <= 10;
    t3 = t9;
    }
    goto L1;
    L2:
    printf("%d\n", t2);
    t10 = 10;
    t12 = t10 >= 1;
    t11 = t12;
    t13 = 0;
    L4:
    if (!(t11)) goto L5;
    {
    t14 = t13 + 1;
    t13 = t14;
    t15 = t10 - 1;
    t10 = t15;
    t16 = t10 >= 1;
    t11 = t16;
    }
    goto L4;
    L5:
    printf("%d\n", t13);
    return 0;
}
