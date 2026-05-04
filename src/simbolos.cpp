#include "simbolos.h"
#include <iostream>
#include <stdexcept>

//Funções auxiliares de conversão de tipo

Tipo stringParaTipo(const std::string& s) {
    if (s == "int")   return Tipo::INT;
    if (s == "float") return Tipo::FLOAT;
    if (s == "bool")  return Tipo::BOOL;
    if (s == "char")  return Tipo::CHAR;
    return Tipo::DESCONHECIDO;
}

std::string tipoParaString(Tipo t) {
    switch (t) {
        case Tipo::INT:   return "int";
        case Tipo::FLOAT: return "float";
        case Tipo::BOOL:  return "bool";
        case Tipo::CHAR:  return "char";
        default:          return "desconhecido";
    }
}

//Métodos da TabelaDeSimbolos

void TabelaDeSimbolos::inserir(const std::string& nome, Tipo tipo) {
    if (existe(nome)) {
        throw std::runtime_error("Erro semântico: variável já declarada: " + nome);
    }
    tabela[nome] = tipo;
}

Tipo TabelaDeSimbolos::buscar(const std::string& nome) const {
    auto it = tabela.find(nome);
    if (it == tabela.end()) {
        throw std::runtime_error("Erro semântico: variável não declarada: " + nome);
    }
    return it->second;
}

bool TabelaDeSimbolos::existe(const std::string& nome) const {
    return tabela.count(nome) > 0;
}

void TabelaDeSimbolos::imprimir() const {
    std::cout << "=== Tabela de Símbolos ===\n";
    for (const auto& par : tabela) {
        std::cout << "  " << par.first << " -> " << tipoParaString(par.second) << "\n";
    }
    std::cout << "==========================\n";
}
