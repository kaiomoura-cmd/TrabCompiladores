#include <stdio.h>
#include <string.h>

enum Estado { OFF, ON };

int duplicar(int t1) {
    int t3;
    /* --- declaracoes de temporarios --- */
    int t2;

    t2 = t1 * 2;
    t3 = t2;
    return t3;
}

void print_status(int t4) {
    /* --- declaracoes de temporarios --- */
    int t5;

    t5 = t4 == 1;
    if (!(t5)) goto L1;
    {
    printf("%s\n", "Estado: LIGADO");
    }
    goto L2;
    L1:
    {
    printf("%s\n", "Estado: DESLIGADO");
    }
    L2:
}


int main() {
    /* --- declaracoes de variaveis --- */
    int t6;
    int t7;
    int t8;
    int t9[5] = {10, 20, 30, 40, 50};
    int t10[2][3] = {{1, 2, 3}, {4, 5, 6}};
    int t11;
    int t12;
    int t18[3];
    /* --- declaracoes de temporarios --- */
    int t13, t14, t15, t16, t17, t19, t20, t21, t22;

    t6 = 5;
    t7 = 10;
    t11 = 1;
    t12 = 0;
    printf("%d\n", t6);
    printf("%d\n", t7);
    t13 = t6 + 2;
    t6 = t13;
    printf("%d\n", t6);
    t14 = t7 - 3;
    t7 = t14;
    printf("%d\n", t7);
    t6++;
    printf("%d\n", t6);
    --t6;
    printf("%d\n", t6);
    printf("%d\n", t9[2]);
    printf("%d\n", t10[1][1]);
    t15 = duplicar(t6);
    t8 = t15;
    printf("%d\n", t8);
    t16 = (int) t11;
    print_status(t16);
    t17 = (int) t12;
    print_status(t17);
    t20 = 4 - 1;
    for (int t19 = 0; t19 < t20; t19++) {
        t18[t19] = t9[1 + t19];
    }
    printf("%d\n", t18[0]);
    printf("%d\n", t18[1]);
    printf("%d\n", t18[2]);
    t22 = 4 - 1;
    printf("[");
    for (int t21 = 0; t21 < t22; t21++) {
        if (t21 > 0) printf(", ");
        printf("%d", t9[1 + t21]);
    }
    printf("]\n");
    return 0;
}
