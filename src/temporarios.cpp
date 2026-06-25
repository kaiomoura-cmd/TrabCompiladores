#include "temporarios.h"
#include <iostream>
#include <unordered_map>

// Gerador De Temporarios

GeradorDeTemporarios::GeradorDeTemporarios() : contador(0), tabela_ref(nullptr) {}

void GeradorDeTemporarios::setTabela(const TabelaDeSimbolos* tab) {
    tabela_ref = tab;
}

std::string GeradorDeTemporarios::novoTemporario() {
    std::string nome;
    do {
        ++contador;
        nome = "t" + std::to_string(contador);
    /* Pula o nome se ja foi declarado pelo usuario (evita colisao) */
    } while (tabela_ref != nullptr && tabela_ref->existe(nome));
    temporarios.push_back(nome);
    return nome;
}

const std::vector<std::string> &GeradorDeTemporarios::getTemporarios() const {
  return temporarios;
}

void GeradorDeTemporarios::reiniciar() {
  temporarios.clear();
}

// Declaracao De Memoria

void DeclaracaoDeMemoria::imprimirDeclaracoes(
    const std::vector<std::string> &temporarios, const TabelaDeSimbolos &tabela,
    Tipo tipoPadrao) const {
  if (temporarios.empty())
    return;

  // Agrupa os temporários por tipo para gerar declarações compactas
  std::unordered_map<std::string, std::vector<std::string>> porTipo;

  for (const auto &temp : temporarios) {
    if (tabela.existePorNomeC(temp)) {
      continue;
    }
    Tipo t = tipoPadrao;
    porTipo[tipoParaString(t)].push_back(temp);
  }

  std::cout << "    /* --- declaracoes de temporarios --- */\n";

  // Imprime uma linha por tipo: "    int t1, t2;"
  for (const auto &entrada : porTipo) {
    std::cout << "    " << entrada.first << " ";
    for (size_t i = 0; i < entrada.second.size(); ++i) {
      if (i > 0)
        std::cout << ", ";
      std::cout << entrada.second[i];
    }
    std::cout << ";\n";
  }

}
