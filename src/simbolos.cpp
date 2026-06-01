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
    return Tipo::DESCONHECIDO;
}

std::string tipoParaString(Tipo t) {
    switch (t) {
        case Tipo::INT:    return "int";
        case Tipo::FLOAT:  return "float";
        case Tipo::BOOL:   return "int";   // bool → int no código intermediário (0/1)
        case Tipo::CHAR:   return "char";
        case Tipo::STRING: return "string";
        default:           return "desconhecido";
    }
}

// Gerenciamento de Escopo

TabelaDeSimbolos::TabelaDeSimbolos() {
    entrarEscopo(); // Cria o escopo global automaticamente
}

void TabelaDeSimbolos::entrarEscopo() {
    // Coloca uma nova "folha transparente" no topo da pilha
    pilha_tabelas.push_back(std::unordered_map<std::string, Tipo>());
}

void TabelaDeSimbolos::sairEscopo() {
    // Joga a folha do topo no lixo (se não for o escopo global)
    if (pilha_tabelas.size() > 1) {
        pilha_tabelas.pop_back();
    }
}

//Métodos da TabelaDeSimbolos

void TabelaDeSimbolos::inserir(const std::string& nome, Tipo tipo) {
    // Olha APENAS para a tabela que está no topo da pilha (.back())
    if (pilha_tabelas.back().count(nome) > 0) {
        std::string msg = "Erro Semantico: Variavel '" + nome + "' ja declarada neste escopo.";
        yyerror(msg.c_str());
        exit(1);
    }
    // Insere a variável no escopo atual
    pilha_tabelas.back()[nome] = tipo;
}

Tipo TabelaDeSimbolos::buscar(const std::string& nome) const {
    int nivel_atual = pilha_tabelas.size() - 1;
    
    for (auto it = pilha_tabelas.rbegin(); it != pilha_tabelas.rend(); ++it) {
        auto found = it->find(nome);
        if (found != it->end()) {
            std::cerr << "'" << nome << "' Escopo Nivel " << nivel_atual << "\n";
            
            return found->second; 
        }
        nivel_atual--; 
    }
    
    std::string msg = "Erro Semantico: Variavel '" + nome + "' nao declarada.";
    yyerror(msg.c_str());
    exit(1);
    return Tipo::DESCONHECIDO; 
}

bool TabelaDeSimbolos::existe(const std::string& nome) const {
    // rbegin() a rend() faz o loop rodar de trás pra frente do escopo mais interno pro mais externo
    for (auto it = pilha_tabelas.rbegin(); it != pilha_tabelas.rend(); ++it) {
        if (it->count(nome) > 0) {
            return true; // Achou em algum escopo!
        }
    }
    return false; // Não existe em lugar nenhum
}

void TabelaDeSimbolos::imprimir() const {
    std::cerr << "\n--- Estado Atual da Tabela de Simbolos ---\n";
    // Percorre todos os escopos, do mais antigo ao mais novo
    for (size_t i = 0; i < pilha_tabelas.size(); ++i) {
        std::cerr << "Escopo Nivel " << i << ":\n";
        if (pilha_tabelas[i].empty()) {
            std::cerr << "  (vazio)\n";
        } else {
            for (const auto& par : pilha_tabelas[i]) {
                std::cerr << "  - " << par.first << " : " << tipoParaString(par.second) << "\n";
            }
        }
    }
    std::cerr << "------------------------------------------\n\n";
}