#!/usr/bin/env bash
# ============================================================
#  executar.sh  —  Pipeline completo Saphira → C-- → execução
#
#  Uso:
#    ./executar.sh arquivo.saphira          # compila e executa
#    ./executar.sh arquivo.saphira --ver    # mostra o C-- gerado
#    ./executar.sh --todos                  # roda todos os testes
#
#  Pipeline interno:
#    1. Saphira  →  C-- (nosso compilador)
#    2. C-- + runtime.h  →  C válido (sed transforma ifFalse→if)
#    3. C  →  executável (gcc -std=c11)
#    4. Executa e mostra resultado
# ============================================================

set -euo pipefail

# ─── Caminhos ────────────────────────────────────────────────
RAIZ="$(cd "$(dirname "$0")" && pwd)"
COMPILADOR="$RAIZ/bin/compilador"
RUNTIME="$RAIZ/runtime/runtime.h"
TMP_CMM="/tmp/saphira_saida.c--"
TMP_C="/tmp/saphira_exec.c"
TMP_BIN="/tmp/saphira_prog"

# ─── Cores ───────────────────────────────────────────────────
VERDE='\033[0;32m'
AZUL='\033[0;34m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NEGRITO='\033[1m'
RESET='\033[0m'

# ─── Verificações iniciais ────────────────────────────────────
if [ ! -f "$COMPILADOR" ]; then
    echo -e "${VERMELHO}[ERRO] Compilador não encontrado. Execute 'make' primeiro.${RESET}"
    exit 1
fi

# ─── Função: compilar e executar um arquivo Saphira ──────────
executar_arquivo() {
    local ARQUIVO="$1"
    local VER="${2:-}"

    if [ ! -f "$ARQUIVO" ]; then
        echo -e "${VERMELHO}[ERRO] Arquivo não encontrado: $ARQUIVO${RESET}"
        return 1
    fi

    local NOME
    NOME=$(basename "$ARQUIVO")

    echo -e "${NEGRITO}${AZUL}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${NEGRITO}${AZUL}  Saphira → C--  │  $NOME${RESET}"
    echo -e "${NEGRITO}${AZUL}╚══════════════════════════════════════════════╝${RESET}"

    # ── Passo 1: Saphira → C-- ──────────────────────────────
    echo -e "${AMARELO}[1/3] Compilando Saphira → C-- ...${RESET}"
    if ! "$COMPILADOR" "$ARQUIVO" > "$TMP_CMM" 2>&1; then
        echo -e "${VERMELHO}[ERRO] Falha na compilação Saphira:${RESET}"
        cat "$TMP_CMM"
        return 1
    fi

    # ── Exibe o C-- se pedido ────────────────────────────────
    if [ "$VER" = "--ver" ]; then
        echo -e "\n${NEGRITO}── Código C-- Gerado ────────────────────────────${RESET}"
        cat -n "$TMP_CMM"
        echo -e "${NEGRITO}─────────────────────────────────────────────────${RESET}\n"
    fi

    # ── Passo 2: C-- → C válido ─────────────────────────────
    echo -e "${AMARELO}[2/3] Copiando código C gerado ...${RESET}"
    cp "$TMP_CMM" "$TMP_C"

    # ── Passo 3: gcc compila ─────────────────────────────────
    echo -e "${AMARELO}[3/3] Compilando C → executável (gcc) ...${RESET}"
    if ! gcc -std=c11 -x c "$TMP_C" -o "$TMP_BIN" 2>&1; then
        echo -e "${VERMELHO}[ERRO] Falha ao compilar o C gerado.${RESET}"
        return 1
    fi

    # ── Executa ──────────────────────────────────────────────
    echo -e "\n${VERDE}${NEGRITO}── Saída do programa ────────────────────────────${RESET}"
    "$TMP_BIN"
    echo -e "${VERDE}${NEGRITO}─────────────────────────────────────────────────${RESET}\n"
}

# ─── Modo --todos ─────────────────────────────────────────────
if [ "${1:-}" = "--todos" ]; then
    echo -e "${NEGRITO}Rodando todos os testes em testes/ ...${RESET}\n"
    PASSOU=0
    FALHOU=0
    for f in "$RAIZ/testes"/*.saphira; do
        if executar_arquivo "$f"; then
            PASSOU=$((PASSOU + 1))
        else
            FALHOU=$((FALHOU + 1))
        fi
    done
    echo -e "${NEGRITO}Resultado: ${VERDE}$PASSOU passou(aram)${RESET}  ${VERMELHO}$FALHOU falhou(aram)${RESET}"
    exit 0
fi

# ─── Uso normal ───────────────────────────────────────────────
if [ $# -eq 0 ]; then
    echo "Uso:"
    echo "  $0 arquivo.saphira          # compila e executa"
    echo "  $0 arquivo.saphira --ver    # mostra o C-- gerado"
    echo "  $0 --todos                  # roda todos os testes"
    exit 0
fi

executar_arquivo "$1" "${2:-}"
