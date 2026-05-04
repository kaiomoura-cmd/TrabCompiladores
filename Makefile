CC = g++
CFLAGS = -std=c++17 -Wall -I src -fpermissive

all:
	bison -d src/sintatico.y -o src/sintatico.tab.c
	flex -o src/lex.yy.c src/lexico.l
	$(CC) $(CFLAGS) src/sintatico.tab.c src/lex.yy.c src/simbolos.cpp src/temporarios.cpp -o bin/compilador

clean:
	rm -f src/*.tab.* src/lex.yy.c bin/compilador