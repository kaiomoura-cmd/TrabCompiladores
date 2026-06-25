#include <stdio.h>
#include <string.h>

int main() {
    /* --- declaracoes de variaveis --- */
    int t1;
    int t2;
    int t6; /* bool */
    int t10;
    int t11; /* bool */
    int t13;
    int t14; /* bool */
    /* --- declaracoes de temporarios --- */
    int t3, t4, t5, t7, t8, t9, t12, t15, t16, t17, t18, t19;

    t2 = 1;
    L1:
    t3 = t2 <= 10;
    if (!(t3)) goto L2;
    t4 = t2 + 1;
    {
    t5 = 3 * t2;
    t1 = t5;
    t7 = t1 / 2;
    t8 = t7 * 2;
    t9 = t1 == t8;
    t6 = t9;
    if (!(t6)) goto L3;
    {
    printf("%d\n", t1);
    }
    L3:
    }
    t2 = t4;
    goto L1;
    L2:
    t10 = 1;
    t12 = t10 <= 2;
    t11 = t12;
    L4:
    if (!(t11)) goto L5;
    {
    t13 = 1;
    t15 = t13 <= 3;
    t14 = t15;
    L6:
    if (!(t14)) goto L7;
    {
    printf("%d\n", t13);
    t16 = t13 + 1;
    t13 = t16;
    t17 = t13 <= 3;
    t14 = t17;
    }
    goto L6;
    L7:
    t18 = t10 + 1;
    t10 = t18;
    t19 = t10 <= 2;
    t11 = t19;
    }
    goto L4;
    L5:
    return 0;
}
