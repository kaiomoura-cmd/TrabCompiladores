#include <stdio.h>
#include <string.h>

int main() {
    /* --- declaracoes de variaveis --- */
    int t1;
    int t2;
    int t3;
    float t5;
    float t6;
    float t7;
    float t9;
    int t12; /* bool */
    int t13; /* bool */
    int t14; /* bool */
    char t17;
    /* --- declaracoes de temporarios --- */
    int t4, t8, t10, t11, t15, t16;

    t1 = 7;
    t2 = 2;
    t4 = t1 / t2;
    t3 = t4;
    printf("%d\n", t3);
    t5 = 3.5;
    t6 = 1.5;
    t8 = t5 + t6;
    t7 = t8;
    printf("%f\n", t7);
    t11 = (float) t1;
    t10 = t11 + t6;
    t9 = t10;
    printf("%f\n", t9);
    t12 = 1;
    t13 = 0;
    t15 = !t13;
    t16 = t12 && t15;
    t14 = t16;
    printf("%d\n", t14);
    t17 = 'A';
    printf("%c\n", t17);
    return 0;
}
