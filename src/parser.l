/* SPDX-License-Identifier: ISC
 * Tomasulo Simulator -- Flex scanner for input files.
 * NOTE: Lexer generator written by an LLM
 *
 * Generates a reentrant scanner that feeds tokens to the Bison
 * grammar (parser.y).  The scanner tracks line numbers so the parser
 * can produce useful error messages.
 *
 * Input syntax (C-like):
 *
 *     cycles {
 *         add.d = 2
 *         mult.d = 4
 *     }
 *
 *     units { add.d = 1, mult.d = 1, ld = 2, sd = 1 }
 *
 *     registers { F4 = 2.0, F6 = 10.0 }   # optional
 *
 *     instructions {
 *         ADDD F1 F2 F3       # comment
 *         L.D  F0 0 R1
 *     }
 *
 * Identifier matching is permissive: punctuation ('.', '_') is stripped
 * and case is folded, so MULT.D == mult_d == MULTD == multd.
 */

%option noyywrap nounput noinput
%option reentrant bison-bridge bison-locations
%option yylineno
%option never-interactive
%option prefix="tom_yy"

%{
#include "tomasulo.h"
#include "parser_internal.h"
#include "parser.tab.h"   /* Bison-generated token codes */

#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

/* Bison renames YYSTYPE/YYLTYPE to TOM_YYSTYPE/TOM_YYLTYPE via
 * %define api.prefix.  Flex's bison-bridge/bison-locations machinery
 * still refers to the unprefixed names, so paper over the gap here. */
#define YYSTYPE TOM_YYSTYPE
#define YYLTYPE TOM_YYLTYPE

#define YY_USER_ACTION                              \
    do {                                            \
        yylloc->first_line   = yylineno;            \
        yylloc->last_line    = yylineno;            \
    } while (0);

/* Normalise an identifier in place: uppercase, drop '.' and '_'.
 * Used to recognise block keywords (cycles, units, ...) in a way
 * that's consistent with how opcode_from_str() treats opcodes. */
static void normalise_ident(char *s)
{
    char *w = s;
    for (char *r = s; *r; r++) {
        if (*r == '.' || *r == '_')
            continue;
        *w++ = (char)toupper((unsigned char)*r);
    }
    *w = '\0';
}
%}

DIGIT      [0-9]
SIGN       [-+]
INT_LIT    {SIGN}?{DIGIT}+
FLOAT_LIT  {SIGN}?({DIGIT}+\.{DIGIT}*|{DIGIT}*\.{DIGIT}+)([eE]{SIGN}?{DIGIT}+)?
EXP_LIT    {SIGN}?{DIGIT}+[eE]{SIGN}?{DIGIT}+
ID         [A-Za-z_][A-Za-z0-9_.]*

%%

[ \t\r]+              { /* skip horizontal whitespace */ }
\n                    { /* skip newlines (yylineno updated automatically) */ }
#[^\n]*               { /* skip '#' comments to end of line */ }
"//"[^\n]*            { /* skip '//' comments to end of line */ }
","                   { /* commas are pure separators */ }
";"                   { /* semicolons too -- harmless statement terminators */ }

"{"                   { return LBRACE; }
"}"                   { return RBRACE; }
"="                   { return EQUALS; }
"("                   { return LPAREN; }
")"                   { return RPAREN; }

    /* Register names: F0..F31 or R0..R31.  Validation happens here so
     * the grammar only ever sees well-formed register indices. */
[FfRr]{DIGIT}+        {
    long idx = strtol(yytext + 1, NULL, 10);
    if (idx < 0 || idx >= MAX_FP_REGISTERS) {
        tom_parse_error(yyextra, *yylloc,
            "register index out of range: '%s' (max %d)",
            yytext, MAX_FP_REGISTERS - 1);
        return TOM_YYerror;
    }
    yylval->reg = (int)idx;
    return REG;
}

{FLOAT_LIT}|{EXP_LIT} {
    yylval->fval = strtod(yytext, NULL);
    return FLOAT;
}

{INT_LIT}             {
    yylval->ival = (int)strtol(yytext, NULL, 10);
    return INT;
}

    /* Generic identifier: could be a block keyword (cycles/units/registers/
     * instructions) or an opcode (ADD.D, MUL.D, L.D, ...).  We normalise
     * once and then check both possibilities.  Anything unrecognised is a
     * parse error. */
{ID}                  {
    char norm[MAX_NAME_LEN + 1];
    size_t n = strlen(yytext);
    if (n > MAX_NAME_LEN)
        n = MAX_NAME_LEN;
    memcpy(norm, yytext, n);
    norm[n] = '\0';
    normalise_ident(norm);

    if (strcmp(norm, "CYCLES") == 0)        return CYCLES;
    if (strcmp(norm, "UNITS") == 0)         return UNITS;
    if (strcmp(norm, "MEMUNITS") == 0)      return UNITS; /* alias */
    if (strcmp(norm, "REGISTERS") == 0)     return REGISTERS;
    if (strcmp(norm, "REGINIT") == 0)       return REGISTERS; /* alias */
    if (strcmp(norm, "INSTRUCTIONS") == 0)  return INSTRUCTIONS;

    Opcode op = opcode_from_str(yytext);
    if (op >= OP_COUNT) {
        tom_parse_error(yyextra, *yylloc,
            "unknown identifier '%s'", yytext);
        return TOM_YYerror;
    }
    yylval->opcode = op;
    return OPCODE;
}

.                     {
    tom_parse_error(yyextra, *yylloc,
        "unexpected character '%c'", yytext[0]);
    return TOM_YYerror;
}

%%
