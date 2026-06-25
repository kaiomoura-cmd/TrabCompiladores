#include <stdio.h>
#include <string.h>

int main() {
    /* --- declaracoes de variaveis --- */
    int t1;
    int t2;
    int t3; /* bool */
    int t6; /* bool */
    /* --- declaracoes de temporarios --- */
    int t4, t5, t7, t8, t9;

    t1 = 15;
    t2 = 8;
    t4 = t1 > t2;
    t3 = t4;
    if (!(t3)) goto L1;
    {
    printf("%d\n", t1);
    }
    L1:
    t5 = t1 > t2;
    if (!(t5)) goto L2;
    {
    printf("%d\n", 1);
    }
    goto L3;
    L2:
    {
    printf("%d\n", 0);
    }
    L3:
    t7 = t1 > 5;
    t8 = t2 < 10;
    t9 = t7 && t8;
    t6 = t9;
    if (!(t6)) goto L4;
    {
    printf("%d\n", 99);
    }
    L4:
    return 0;
}
