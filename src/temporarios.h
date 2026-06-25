#ifndef TEMPORARIOS_H
#define TEMPORARIOS_H

#include <string>
#include <vector>
#include <unordered_map>
#include "simbolos.h"

// Gerador de Temporários

class GeradorDeTemporarios {
public:
    GeradorDeTemporarios();

    // Conecta o gerador à tabela de símbolos para evitar colisão de nomes.
    void setTabela(const TabelaDeSimbolos* tab);

    // Retorna um novo temporário único, pulando nomes já usados pelo usuário.
    std::string novoTemporario();

    // Registra o tipo de um temporário (para declaração correta no C--).
    void definirTipo(const std::string& nome, Tipo tipo);

    // Retorna o tipo de um temporário (default: INT se não registrado).
    Tipo getTipo(const std::string& nome) const;

    // Retorna a lista de todos os temporários gerados até agora.
    const std::vector<std::string>& getTemporarios() const;

    // Retorna o mapa de tipos dos temporários.
    const std::unordered_map<std::string, Tipo>& getTiposTemporarios() const;

    // Reinicia o contador e limpa o mapa de tipos.
    void reiniciar();

private:
    int contador;
    std::vector<std::string> temporarios;
    std::unordered_map<std::string, Tipo> tipos_temporarios;
    const TabelaDeSimbolos* tabela_ref;  // ponteiro fraco, não deleta
};

// Declaração de Memória

class DeclaracaoDeMemoria {
public:
    /* Gera e imprime o bloco de declarações no formato:
        int T1, T2;
        float T3;
     O tipo de cada temporário é consultado no mapa tipos_temporarios.
     Temporários sem tipo registrado recebem int.*/
    void imprimirDeclaracoes(
        const std::vector<std::string>& temporarios,
        const TabelaDeSimbolos& tabela,
        const std::unordered_map<std::string, Tipo>& tipos_temporarios
    ) const;
};

#endif 
