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

literal = "null" | number | float_number | """ ascii_char """

basic_type = void
           | i8 | i16 | i32 | i64
           | u8 | u16 | u32 | u64
type = void 
     | "*" type 
     | "*" "own" type 
     | "[" [ number | "_" ]? "]" type
     | "mut" type
     | "(" type

bin_bool_op = "==" | "!=" | "<" | ">" | "<=" | ">="
bin_arith_op = "+" | "-" | "/" | "*" | "<<" | ">>" | "&" | "|" | "^" | "++" | "**"
bin_op = bin_bool_op | bin_arith_op
prefix_bool_op = "!"
prefix_arith_op = "-" | "~"
prefix_op = prefix_bool_op | prefix_arith_op

assign_op = "=" | bin_arith_op"="

capture = "|" ident "|"

expr = prefix_op expr
     | expr bin_op expr
     | "(" expr ")" 
     | expr ".*" 
     | expr ".&"
     | expr ".!"
     | expr ".?"
     | expr "." expr
     | expr "(" expr* ")"
     | expr "onerr" capture? expr
     | expr "onerr" capture? "do" "{" stmt* "}"
     | expr "else" expr
     | expr "else" "do" "{" stmt* "}"

var = ident | "(" var "," var [ "," var ]* ")"
typed_var = var ":" type

define_stmt = [ [ "let" | "mut" ] typed_var | "_" ] "=" expr ";"
assign_stmt = ident assign_op expr ";"

return_stmt = "return" expr? ";"
loop_op_stmt = [ "break" | "continue" ] ";"
if_stmt = "if" expr "{" stmt* "}" [ "else if" "{" stmt* "}" ]* [ "else" "{" stmt* "}" ]?
for_stmt = "for" literal "in" expr "{" stmt* "}"
while_stmt = "while" expr "{" stmt* "}"
stmt = assign_stmt | return_stmt | loop_op_stmt | if_stmt | for_stmt | while_stmt

func_def = "fn" ident "(" [ typed-var "," ]* ")" "->" type "{" stmt* "}"

struct_def = "struct" ident "{" [ typed_var "," ]* func_def* "}"
```

### Implemented Grammar

