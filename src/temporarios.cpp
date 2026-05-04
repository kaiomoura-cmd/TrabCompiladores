#include "temporarios.h"
#include <iostream>
#include <unordered_map>

// Gerador De Temporarios

GeradorDeTemporarios::GeradorDeTemporarios() : contador(0) {}

std::string GeradorDeTemporarios::novoTemporario() {
    ++contador;
    std::string nome = "T" + std::to_string(contador);
    temporarios.push_back(nome);
    return nome;
}

const std::vector<std::string>& GeradorDeTemporarios::getTemporarios() const {
    return temporarios;
}

void GeradorDeTemporarios::reiniciar() {
    contador = 0;
    temporarios.clear();
}

//Declaracao De Memoria

void DeclaracaoDeMemoria::imprimirDeclaracoes(
    const std::vector<std::string>& temporarios,
    const TabelaDeSimbolos& tabela,
    Tipo tipoPadrao
) const {
    if (temporarios.empty()) return;

    // Agrupa os temporários por tipo para gerar declarações compactas 
    std::unordered_map<std::string, std::vector<std::string>> porTipo;

    for (const auto& temp : temporarios) {
        Tipo t = tipoPadrao;

        // Se o temporário existir na tabela de símbolos, usa o tipo de lá
        if (tabela.existe(temp)) {
            t = tabela.buscar(temp);
        }

        porTipo[tipoParaString(t)].push_back(temp);
    }

    std::cout << "/* --- Declarações de temporários --- */\n";

    // Imprime uma linha por tipo: "int T1, T2"
    for (const auto& entrada : porTipo) {
        std::cout << entrada.first << " ";
        for (size_t i = 0; i < entrada.second.size(); ++i) {
            if (i > 0) std::cout << ", ";
            std::cout << entrada.second[i];
        }
        std::cout << ";\n";
    }

    std::cout << "/* ----------------------------------- */\n";
}
