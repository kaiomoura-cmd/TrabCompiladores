#include "simbolos.h"
#include <iostream>
#include <stdexcept>
#include <cstdlib>

extern void yyerror(const char *s);

//Funções auxiliares de conversão de tipo

Tipo stringParaTipo(const std::string& s) {
    if (s == "int")   return Tipo::INT;
    if (s == "float") return Tipo::FLOAT;
    if (s == "bool")  return Tipo::BOOL;
    if (s == "char")  return Tipo::CHAR;
    if (s == "string") return Tipo::STRING;
    if (s == "void")  return Tipo::VOID;
    return Tipo::DESCONHECIDO;
}

std::string tipoParaString(Tipo t) {
    switch (t) {
        case Tipo::INT:    return "int";
        case Tipo::FLOAT:  return "float";
        case Tipo::BOOL:   return "int";   // bool → int no código intermediário (0/1)
        case Tipo::CHAR:   return "char";
        case Tipo::STRING: return "string";
        case Tipo::VOID:   return "void";
        default:           return "desconhecido";
    }
}

// Gerenciamento de Escopo

TabelaDeSimbolos::TabelaDeSimbolos() {
    entrarEscopo(); // Cria o escopo global automaticamente
}

void TabelaDeSimbolos::entrarEscopo() {
    // Coloca uma nova "folha transparente" no topo da pilha
    pilha_tabelas.push_back(std::unordered_map<std::string, Simbolo>());
}

void TabelaDeSimbolos::sairEscopo() {
    // Joga a folha do topo no lixo (se não for o escopo global)
    if (pilha_tabelas.size() > 1) {
        pilha_tabelas.pop_back();
    }
}

//Métodos da TabelaDeSimbolos

void TabelaDeSimbolos::inserir(const std::string& nome, Tipo tipo) {
    Simbolo simb;
    simb.nome = nome;
    simb.tipo = tipo;
    inserirSimbolo(nome, simb);
}

void TabelaDeSimbolos::inserirSimbolo(const std::string& nome, const Simbolo& simb) {
    // Olha APENAS para a tabela que está no topo da pilha (.back())
    if (pilha_tabelas.back().count(nome) > 0) {
        std::string msg = "Erro Semantico: Identificador '" + nome + "' ja declarado neste escopo.";
        yyerror(msg.c_str());
        exit(1);
    }
    // Insere o símbolo no escopo atual
    pilha_tabelas.back()[nome] = simb;
}

Tipo TabelaDeSimbolos::buscar(const std::string& nome) const {
    return buscarSimbolo(nome).tipo;
}

Simbolo TabelaDeSimbolos::buscarSimbolo(const std::string& nome) const {
    for (auto it = pilha_tabelas.rbegin(); it != pilha_tabelas.rend(); ++it) {
        auto found = it->find(nome);
        if (found != it->end()) {
            return found->second; 
        }
    }
    
    std::string msg = "Erro Semantico: Variavel ou identificador '" + nome + "' nao declarado.";
    yyerror(msg.c_str());
    exit(1);
    Simbolo vazio;
    return vazio;
}

bool TabelaDeSimbolos::existe(const std::string& nome) const {
    for (auto it = pilha_tabelas.rbegin(); it != pilha_tabelas.rend(); ++it) {
        if (it->count(nome) > 0) {
            return true; // Achou!
        }
    }
    return false;
}

void TabelaDeSimbolos::imprimir() const {
    std::cerr << "\n--- Estado Atual da Tabela de Simbolos ---\n";
    for (size_t i = 0; i < pilha_tabelas.size(); ++i) {
        std::cerr << "Escopo Nivel " << i << ":\n";
        if (pilha_tabelas[i].empty()) {
            std::cerr << "  (vazio)\n";
        } else {
            for (const auto& par : pilha_tabelas[i]) {
                std::cerr << "  - " << par.first << " : " << tipoParaString(par.second.tipo)
                          << (par.second.eh_funcao ? " [funcao]" : "")
                          << (par.second.eh_vetor ? " [vetor]" : "")
                          << (par.second.eh_matriz ? " [matriz]" : "") << "\n";
            }
        }
    }
    std::cerr << "------------------------------------------\n\n";
}