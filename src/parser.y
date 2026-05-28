/* SPDX-License-Identifier: MIT
 * Tomasulo Simulator -- Bison grammar for input files.
 *
 * Input file grammar (informal, C-like):
 *
 *   input            : block+
 *                    ;
 *
 *   block            : cycles_block
 *                    | units_block
 *                    | registers_block
 *                    | instructions_block
 *                    ;
 *
 *   cycles_block     : 'cycles' '{' (OPCODE '=' INT)*           '}' ;
 *   units_block      : 'units'  '{' (OPCODE '=' INT)*           '}' ;
 *   registers_block  : 'registers' '{' (REG '=' number)*        '}' ;
 *   instructions_block : 'instructions' '{' instruction*        '}' ;
 *
 *   instruction      : OPCODE REG REG REG                       (arithmetic)
 *                    | OPCODE REG INT REG                       (L.D/S.D, simple form)
 *                    | OPCODE REG INT '(' REG ')'               (MIPS offset(base))
 *                    ;
 *
 *   number           : INT | FLOAT ;
 *
 * Items inside a block may be separated by whitespace, newlines,
 * commas, or semicolons (all handled by the lexer).  '#' and '//'
 * comments run to end of line.  Block keywords and opcodes are
 * matched case-insensitively with '.'/'_' ignored, so mult.d ==
 * MULT_D == MULTD.
 */

%define api.pure full
%define api.prefix {tom_yy}
%define parse.error verbose
%locations
%lex-param   {void *scanner}
%parse-param {void *scanner}
%parse-param {ParseContext *ctx}

%code requires {
#include "tomasulo.h"
#include "parser_internal.h"
}

%code provides {
/* Bison generates tom_yyparse() etc.  These typedefs help the lexer
 * use the YYSTYPE/YYLTYPE definitions without circular includes. */
#ifndef YY_TYPEDEF_YY_SCANNER_T
#define YY_TYPEDEF_YY_SCANNER_T
typedef void *yyscan_t;
#endif
}

%code {
#include "parser.tab.h"

/* Forward declarations to silence -Wmissing-prototypes for the
 * generated scanner functions used from the parser actions. */
int  tom_yylex(TOM_YYSTYPE *yylval_param, TOM_YYLTYPE *yylloc_param, void *yyscanner);
void tom_yyerror(TOM_YYLTYPE *loc, void *scanner, ParseContext *ctx, const char *msg);

/* Map an Opcode to the reservation-station type it consumes.  Every
 * opcode we know about has a corresponding RS pool, so this is total. */
static RSType op_to_rs_type(Opcode op)
{
    switch (op) {
    case OP_ADDD:
    case OP_SUBD:  return RS_ADD;
    case OP_MULTD:
    case OP_DIVD:  return RS_MULT;
    case OP_LD:    return RS_LOAD;
    case OP_SD:    return RS_STORE;
    default:       return RS_ADD; /* unreachable: lexer rejects bad opcodes */
    }
}

/* Lazily initialise the simulator the first time we need it -- either
 * because we're about to set initial register values, or because we're
 * about to start consuming instructions.  The grammar is liberal about
 * block ordering, so we can't tie this to a single rule. */
static void ensure_sim_ready(ParseContext *ctx)
{
    if (!ctx->sim_ready) {
        sim_init(ctx->sim, ctx->cfg);
        ctx->sim_ready = true;
    }
}
}

%union {
    int      ival;
    double   fval;
    int      reg;     /* numeric register index */
    Opcode   opcode;
}

/* Block keywords. */
%token CYCLES UNITS REGISTERS INSTRUCTIONS

/* Punctuation. */
%token LBRACE RBRACE EQUALS LPAREN RPAREN

/* Value-bearing terminals. */
%token <ival>   INT
%token <fval>   FLOAT
%token <reg>    REG
%token <opcode> OPCODE

%type  <fval>   number

%start input

%%

input
    : blocks
    ;

blocks
    : /* empty */
    | blocks block
    ;

block
    : cycles_block
    | units_block
    | registers_block
    | instructions_block
    ;

/* ── cycles { OPCODE = INT, ... } ───────────────────────────────── */

cycles_block
    : CYCLES LBRACE cycles_items RBRACE
    ;

cycles_items
    : /* empty */
    | cycles_items cycles_item
    ;

cycles_item
    : OPCODE EQUALS INT
        {
            ctx->cfg->latency[$1] = $3;
        }
    ;

/* ── units { OPCODE = INT, ... } ────────────────────────────────── */

units_block
    : UNITS LBRACE units_items RBRACE
    ;

units_items
    : /* empty */
    | units_items units_item
    ;

units_item
    : OPCODE EQUALS INT
        {
            RSType t = op_to_rs_type($1);
            ctx->cfg->num_rs[t] = $3;
        }
    ;

/* ── registers { Fx = number, ... } ─────────────────────────────── */

registers_block
    : REGISTERS LBRACE
        { ensure_sim_ready(ctx); }
      register_items
      RBRACE
    ;

register_items
    : /* empty */
    | register_items register_item
    ;

register_item
    : REG EQUALS number
        {
            sim_set_reg(ctx->sim, $1, $3);
        }
    ;

number
    : INT    { $$ = (double)$1; }
    | FLOAT  { $$ = $1; }
    ;

/* ── instructions { ... } ───────────────────────────────────────── */

instructions_block
    : INSTRUCTIONS LBRACE
        { ensure_sim_ready(ctx); }
      instructions
      RBRACE
    ;

instructions
    : /* empty */
    | instructions instruction
    ;

instruction
    : OPCODE REG REG REG
        {
            if ($1 == OP_LD || $1 == OP_SD) {
                tom_parse_error(ctx, @1,
                    "memory opcode '%s' needs an offset, not three registers",
                    opcode_name($1));
                YYERROR;
            }
            Instruction inst = {
                .op = $1, .dest = $2, .src1 = $3, .src2 = $4,
                .imm = 0,
            };
            if (!sim_add_instruction(ctx->sim, inst)) {
                tom_parse_error(ctx, @1, "too many instructions (max %d)",
                                MAX_INSTRUCTIONS);
                YYERROR;
            }
        }
    | OPCODE REG INT REG
        {
            if ($1 != OP_LD && $1 != OP_SD) {
                tom_parse_error(ctx, @1,
                    "opcode '%s' doesn't take an immediate offset",
                    opcode_name($1));
                YYERROR;
            }
            Instruction inst = {
                .op = $1, .dest = $2, .src1 = $4, .src2 = -1,
                .imm = $3,
            };
            if (!sim_add_instruction(ctx->sim, inst)) {
                tom_parse_error(ctx, @1, "too many instructions (max %d)",
                                MAX_INSTRUCTIONS);
                YYERROR;
            }
        }
    | OPCODE REG INT LPAREN REG RPAREN
        {
            if ($1 != OP_LD && $1 != OP_SD) {
                tom_parse_error(ctx, @1,
                    "opcode '%s' doesn't take 'offset(base)'",
                    opcode_name($1));
                YYERROR;
            }
            Instruction inst = {
                .op = $1, .dest = $2, .src1 = $5, .src2 = -1,
                .imm = $3,
            };
            if (!sim_add_instruction(ctx->sim, inst)) {
                tom_parse_error(ctx, @1, "too many instructions (max %d)",
                                MAX_INSTRUCTIONS);
                YYERROR;
            }
        }
    ;

%%

void tom_yyerror(TOM_YYLTYPE *loc, void *scanner, ParseContext *ctx,
                 const char *msg)
{
    (void)scanner;
    tom_parse_error(ctx, *loc, "%s", msg);
}
