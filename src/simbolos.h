#ifndef SIMBOLOS_H
#define SIMBOLOS_H

#include <string>
#include <unordered_map>
#include <stdexcept>
#include <vector>

// Tipos suportados pelo C--
enum class Tipo {
    INT,
    FLOAT,
    BOOL,
    CHAR,
    DESCONHECIDO
};

// Converte uma string para o enum Tipo e Converte o enum Tipo de volta para string 
Tipo stringParaTipo(const std::string& s);
std::string tipoParaString(Tipo t);


// Tabela de Símbolos para armazenar variáveis declaradas e seus tipos.

class TabelaDeSimbolos {
public:
    TabelaDeSimbolos();

    // Métodos de Controle de Escopo
    void entrarEscopo();
    void sairEscopo();

    void inserir(const std::string& nome, Tipo tipo);
    Tipo buscar(const std::string& nome) const;
    bool existe(const std::string& nome) const;
    void imprimir() const;

private:
    // Pilha de tabelas
    std::vector<std::unordered_map<std::string, Tipo>> pilha_tabelas;
};

#endif 
