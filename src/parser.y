/* SPDX-License-Identifier: MIT
 * Tomasulo Simulator -- Bison grammar for input files.
 *
 * Grammar (informal):
 *
 *   input        : config_section reg_init_section? instr_section ;
 *
 *   config_section : CONFIG_BEGIN config_item* CONFIG_END ;
 *   config_item    : CYCLES OPCODE INT
 *                  | UNITS  OPCODE INT
 *                  | MEM_UNITS OPCODE INT
 *                  ;
 *
 *   reg_init_section : REG_INIT_BEGIN reg_init* REG_INIT_END ;
 *   reg_init         : REG number ;
 *
 *   instr_section : INSTRUCTIONS_BEGIN instruction* INSTRUCTIONS_END ;
 *   instruction   : OPCODE REG REG REG          (arithmetic)
 *                 | OPCODE REG INT REG          (L.D/S.D, simple form)
 *                 | OPCODE REG INT LPAREN REG RPAREN   (MIPS offset(base))
 *                 ;
 *
 *   number : INT | FLOAT ;
 *
 * Whitespace, newlines and '#' comments are skipped in the lexer, so the
 * grammar is purely token-driven.  Commas act as token separators and are
 * also discarded by the lexer.
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

/* Map an Opcode to the reservation-station type it consumes. */
static int op_to_rs_type(Opcode op, RSType *out)
{
    switch (op) {
    case OP_ADDD:
    case OP_SUBD:  *out = RS_ADD;   return 0;
    case OP_MULTD:
    case OP_DIVD:  *out = RS_MULT;  return 0;
    case OP_LD:    *out = RS_LOAD;  return 0;
    case OP_SD:    *out = RS_STORE; return 0;
    default:       return -1;
    }
}
}

%union {
    int      ival;
    double   fval;
    int      reg;     /* numeric register index */
    Opcode   opcode;
}

/* Section delimiters. */
%token CONFIG_BEGIN CONFIG_END
%token REG_INIT_BEGIN REG_INIT_END
%token INSTRUCTIONS_BEGIN INSTRUCTIONS_END

/* Config keywords. */
%token CYCLES UNITS MEM_UNITS

/* Punctuation. */
%token LPAREN RPAREN

/* Value-bearing terminals. */
%token <ival>   INT
%token <fval>   FLOAT
%token <reg>    REG
%token <opcode> OPCODE

%type  <fval>   number

%start input

%%

input
    : config_section opt_reg_init instr_section
    ;

opt_reg_init
    : /* empty */
    | reg_init_section
    ;

/* ── Config ─────────────────────────────────────────────────────── */

config_section
    : CONFIG_BEGIN config_items CONFIG_END
    ;

config_items
    : /* empty */
    | config_items config_item
    ;

config_item
    : CYCLES OPCODE INT
        {
            ctx->cfg->latency[$2] = $3;
        }
    | UNITS OPCODE INT
        {
            RSType t;
            if (op_to_rs_type($2, &t) != 0) {
                tom_parse_error(ctx, @2,
                    "UNITS not applicable to opcode '%s'",
                    opcode_name($2));
                YYERROR;
            }
            ctx->cfg->num_rs[t] = $3;
        }
    | MEM_UNITS OPCODE INT
        {
            RSType t;
            if (op_to_rs_type($2, &t) != 0 ||
                ($2 != OP_LD && $2 != OP_SD)) {
                tom_parse_error(ctx, @2,
                    "MEM_UNITS only applies to L.D / S.D, got '%s'",
                    opcode_name($2));
                YYERROR;
            }
            ctx->cfg->num_rs[t] = $3;
        }
    ;

/* ── Register init (optional) ───────────────────────────────────── */

reg_init_section
    : REG_INIT_BEGIN { ctx->sim_ready = true; sim_init(ctx->sim, ctx->cfg); }
      reg_inits
      REG_INIT_END
    ;

reg_inits
    : /* empty */
    | reg_inits reg_init
    ;

reg_init
    : REG number
        {
            sim_set_reg(ctx->sim, $1, $2);
        }
    ;

number
    : INT    { $$ = (double)$1; }
    | FLOAT  { $$ = $1; }
    ;

/* ── Instructions ───────────────────────────────────────────────── */

instr_section
    : INSTRUCTIONS_BEGIN
        {
            /* If no REG_INIT section was present, initialise the
             * simulator now so it's ready to accept instructions. */
            if (!ctx->sim_ready) {
                sim_init(ctx->sim, ctx->cfg);
                ctx->sim_ready = true;
            }
        }
      instructions
      INSTRUCTIONS_END
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
