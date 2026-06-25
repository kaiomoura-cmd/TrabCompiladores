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
    STRING,
    VOID,
    DESCONHECIDO
};

// Converte uma string para o enum Tipo e Converte o enum Tipo de volta para string 
Tipo stringParaTipo(const std::string& s);
std::string tipoParaString(Tipo t);

// Estrutura rica de símbolo
struct Simbolo {
    std::string nome;
    std::string nome_c; // Nome correspondente no código C intermediário
    Tipo tipo = Tipo::DESCONHECIDO;
    bool eh_vetor = false;
    bool eh_matriz = false;
    bool eh_jagged = false;
    int dim1 = 0;
    int dim2 = 0;
    
    // Funções
    bool eh_funcao = false;
    Tipo tipo_retorno = Tipo::DESCONHECIDO;
    std::vector<Tipo> tipos_parametros;
    
    // Enums
    bool eh_enum_const = false;
    int valor_enum = 0;
    std::string nome_enum_tipo;
};

// Tabela de Símbolos para armazenar variáveis declaradas e seus tipos.
class TabelaDeSimbolos {
public:
    TabelaDeSimbolos();

    // Métodos de Controle de Escopo
    void entrarEscopo();
    void sairEscopo();

    void inserir(const std::string& nome, Tipo tipo);
    void inserirSimbolo(const std::string& nome, const Simbolo& simb);
    
    Tipo buscar(const std::string& nome) const;
    Simbolo buscarSimbolo(const std::string& nome) const;
    
    bool existe(const std::string& nome) const;
    bool existePorNomeC(const std::string& nome_c) const;
    void imprimir() const;

private:
    // Pilha de tabelas que armazena a estrutura rica Simbolo
    std::vector<std::unordered_map<std::string, Simbolo>> pilha_tabelas;
};

#endif 
