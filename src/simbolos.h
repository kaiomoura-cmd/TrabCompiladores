#ifndef SIMBOLOS_H
#define SIMBOLOS_H

#include <string>
#include <unordered_map>
#include <stdexcept>

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
    // Insere uma variável na tabela e lança std::runtime_error se a variável já foi declarada.

    void inserir(const std::string& nome, Tipo tipo);

    // Retorna o tipo de uma variável lança std::runtime_error se a variável não foi declarada.
 
    Tipo buscar(const std::string& nome) const;

    // Retorna true se a variável já existe na tabela.
    bool existe(const std::string& nome) const;

    // Imprime todas as entradas da tabela.
    void imprimir() const;

private:
    std::unordered_map<std::string, Tipo> tabela;
};

#endif 
