<!-- SPDX-License-Identifier: MIT -->
# Grammar of atium

I will be using this file to collect ideas on how to design the language and potentially track what of it is implemented.

### Planned Grammar

```
letter = "a" | ... | "z" | "A" | ... | "Z"
digit = "0" | ... | "9"

ident = [ letter | "_" ] [ letter | "_" | digit ]*

dec_num = digit [ digit | "_" ]*
bin_digit = "0" | "1"
bin_num = "0b" bin_digit [ bin_digit | "_" ]*
oct_digit = "0" | ... | "7"
oct_num = "0o" oct_digit [ oct_digit | "_" ]*
hex_digit = digit | "a" | ... | "f"
hex_num = "0x" hex_digit [ hex_digit | "_" ]*
number = dec_num | bin_num | oct_num | hex_num

float_number = dec_num "." dec_num

string = '"' char* '"'

literal = "null" | number | float_number | "'" ascii_char "'"

basic_type = "void"
           | "bool"
           | "i8" | "i16" | "i32" | "i64"
           | "u8" | "u16" | "u32" | "u64"

bin_bool_op  = "==" | "!=" | "<" | ">" | "<=" | ">="
bin_logic_op = "and" | "or"
bin_arith_op = "+" | "-" | "/" | "*" | "<<" | ">>" | "&" | "|" | "^" | "++" | "**"
bin_op = bin_bool_op | bin_logic_op | bin_arith_op
prefix_bool_op = "!"
prefix_arith_op = "-" | "~"
prefix_op = prefix_bool_op | prefix_arith_op

assign_op = "=" | bin_arith_op "="

capture = "|" [ ident | typed_var ] "|"

struct_expr    = "struct" "{" [ typed_var "," ]* "}"
enum_expr      = "enum"   "{" [ ident    "," ]* "}"
union_expr     = "union" [ "(" [ "enum" | expr ] ")" ]? "{" [ typed_var "," ]* "}"
interface_expr = "interface"  "{" [ typed_var "," ]* "}"
fn_expr        = "fn" "(" [ typed_var [ "," typed_var ]* ]? ")" "->" expr "{" stmt* "}"

expr = ident
     | literal
     | "true" | "false"
     | string
     | prefix_op expr
     | expr bin_op expr
     | expr ".." expr
     | "(" expr ")"
     | expr ".*"
     | expr ".&"
     | expr ".!"
     | expr ".?"
     | expr "." ident
     | expr "(" [ expr [ "," expr ]* ]? ")"
     | expr "onerr" capture? expr
     | expr "onerr" capture? "do" "{" stmt* "}"
     | expr "else" expr
     | expr "else" "do" "{" stmt* "}"
     | basic_type
     | struct_expr
     | enum_expr
     | union_expr
     | interface_expr
     | fn_expr

var = ident | "(" var "," var [ "," var ]* ")"
typed_var = var ":" expr

define_stmt = "let" "mut"? [ var | typed_var | var "." ident ] "=" expr ";"
ignore_define_stmt = "_" "=" expr ";"
assign_stmt = ident assign_op expr ";"

return_stmt  = "return" expr? ";"
loop_op_stmt = ( "break" | "continue" ) ";"
if_stmt      = "if" expr "{" stmt* "}" [ "else" "if" expr "{" stmt* "}" ]* [ "else" "{" stmt* "}" ]?
for_stmt     = "for" ident "in" expr "{" stmt* "}"
while_stmt   = "while" expr "{" stmt* "}"
stmt = define_stmt | ignore_define_stmt | assign_stmt | return_stmt | loop_op_stmt | if_stmt | for_stmt | while_stmt

program = define_stmt*

```
