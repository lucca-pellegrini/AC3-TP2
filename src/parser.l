/* SPDX-License-Identifier: MIT
 * Tomasulo Simulator -- Flex scanner for input files.
 *
 * Generates a reentrant scanner that feeds tokens to the Bison
 * grammar (parser.y).  The scanner tracks line numbers so the parser
 * can produce useful error messages.
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
#[^\n]*               { /* skip comments to end of line */ }
","                   { /* commas are pure separators */ }

"("                   { return LPAREN; }
")"                   { return RPAREN; }

"CONFIG_BEGIN"        { return CONFIG_BEGIN; }
"CONFIG_END"          { return CONFIG_END; }
"REG_INIT_BEGIN"      { return REG_INIT_BEGIN; }
"REG_INIT_END"        { return REG_INIT_END; }
"INSTRUCTIONS_BEGIN"  { return INSTRUCTIONS_BEGIN; }
"INSTRUCTIONS_END"    { return INSTRUCTIONS_END; }

    /* Case-insensitive keywords for config directives. */
[Cc][Yy][Cc][Ll][Ee][Ss]         { return CYCLES; }
[Uu][Nn][Ii][Tt][Ss]             { return UNITS; }
[Mm][Ee][Mm]_[Uu][Nn][Ii][Tt][Ss] { return MEM_UNITS; }

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

    /* Opcode identifiers: ADD.D, ADDD, SUB.D, MUL.D, DIV.D, L.D, S.D, etc.
     * We let opcode_from_str() decide which strings are valid; anything
     * unrecognised becomes a parse error. */
{ID}                  {
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
