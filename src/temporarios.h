#ifndef TEMPORARIOS_H
#define TEMPORARIOS_H

#include <string>
#include <vector>
#include "simbolos.h"

// Gerador de Temporários

class GeradorDeTemporarios {
public:
    GeradorDeTemporarios();

    // Conecta o gerador à tabela de símbolos para evitar colisão de nomes.
    void setTabela(const TabelaDeSimbolos* tab);

    // Retorna um novo temporário único, pulando nomes já usados pelo usuário.
    std::string novoTemporario();

    // Retorna a lista de todos os temporários gerados até agora.
    const std::vector<std::string>& getTemporarios() const;

    // Reinicia o contador.
    void reiniciar();

private:
    int contador;
    std::vector<std::string> temporarios;
    const TabelaDeSimbolos* tabela_ref;  // ponteiro fraco, não deleta
};

// Declaração de Memória

class DeclaracaoDeMemoria {
public:
    /* Gera e imprime o bloco de declarações no formato:
        int T1, T2;
        float T3;
     O tipo padrão de temporários é int, a menos que o nome exista na tabela de símbolos com outro tipo.*/
    void imprimirDeclaracoes(
        const std::vector<std::string>& temporarios,
        const TabelaDeSimbolos& tabela,
        Tipo tipoPadrao = Tipo::INT
    ) const;
};

#endif 
