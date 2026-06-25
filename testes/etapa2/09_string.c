#include <stdio.h>
#include <string.h>

int main() {
    /* --- declaracoes de variaveis --- */
    char* t1 = NULL;
    char* t2 = NULL;
    char* t3 = NULL;
    char* t5 = NULL;
    char* t7 = NULL;
    /* --- declaracoes de temporarios --- */
    int t4, t6;

    t1 = strdup("");
    t2 = strdup("");
    t3 = strdup("");
    { char t_read_buf[1024]; scanf("%s", t_read_buf); free(t1); t1 = strdup(t_read_buf); }
    { char t_read_buf[1024]; scanf("%s", t_read_buf); free(t2); t2 = strdup(t_read_buf); }
    free(t3); t3 = strdup("Mundo");
    t5 = malloc((t1 ? strlen(t1) : 0) + (t2 ? strlen(t2) : 0) + 1);
    t5[0] = '\0';
    if (t1) strcpy(t5, t1);
    if (t2) strcat(t5, t2);
    free(t1);
    t1 = t5;
    t7 = malloc((t1 ? strlen(t1) : 0) + (t3 ? strlen(t3) : 0) + 1);
    t7[0] = '\0';
    if (t1) strcpy(t7, t1);
    if (t3) strcat(t7, t3);
    free(t1);
    t1 = t7;
    printf("%s\n", t1);
    return 0;
}
