all: clean y.tab.c lex.yy.c
	gcc lex.yy.c y.tab.c -lfl -o calc

y.tab.c: B112040016.y
	bison -d -o y.tab.c --defines=y.tab.h B112040016.y

lex.yy.c: B112040016.l
	flex B112040016.l

clean:
	rm -f calc lex.yy.c y.tab.c y.tab.h