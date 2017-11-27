(******************************************************************)
(* Lexer header *)
(******************************************************************)

{
  open Parser
  open Lexing

  type mode =
    | M
    | T
    | CMD of string

  type loc = Lexing.position * Lexing.position

  exception Lexical_error of
    loc (* error segment - start and end pos *)
    * (mode * loc) list (* stack of open modes *)
    * string (* explanation *)

  let loc lexbuf = (lexeme_start_p lexbuf, lexeme_end_p lexbuf)

  let lex_error lexbuf stack s =
    Printf.ksprintf (fun s -> raise (Lexical_error(loc lexbuf, stack, s))) s

(******************************************************************)
(* Helper functions for lexing strings *)
(******************************************************************)

  let st = ref []

  let get_stack () = !st

  let get_mode =
      match !st with
        | (m,_)::_ -> m
        | [] -> T

  let begin_mode m lexbuf =
      st := (m , loc lexbuf) :: !st;
      match m with
        | M -> MATH_BEGIN
        | T -> TEXT_BEGIN
        | CMD apply -> CMD_BEGIN apply

  let end_mode lexbuf =
      match !st with
        | (m,_)::rem ->
            st := rem;
            ( match m with
              | M -> MATH_END
              | T -> TEXT_END
              | CMD _ -> CMD_END )
        | [] -> lex_error lexbuf !st "mismatched delimiters"

  let end_cmd lexbuf =
    match !st with
     | (CMD _, _)::rem ->
            st := rem; CMD_END
     | _ -> STRING ""

  let reset_st () =
      st := []

  let top_level () =
      !st = []

  let lex_error lexbuf s = lex_error lexbuf (get_stack ()) s

  let string_buffer = Buffer.create 256

  let reset_string_buffer () = Buffer.reset string_buffer

  let get_stored_string () = Buffer.contents string_buffer


let char_for_backslash = function
  | 'n' -> '\010'
  | 'r' -> '\013'
  | 'b' -> '\008'
  | 't' -> '\009'
  | c   -> c


  let comment_buf = Buffer.create 128

  let comment_nests = ref 0

  let start_comment () =
    incr comment_nests;
    Buffer.add_string comment_buf "/*"

  (* Close the current comment. If we are still in a comment, raise Exit.
     Else, return a COMMENT token containing the whole comment. *)
  let end_comment () =
    decr comment_nests;
    Buffer.add_string comment_buf "*/";
    if !comment_nests >= 1 then raise Exit;
    let s = Buffer.contents comment_buf in
    Buffer.reset comment_buf;
    COMMENT s

  let token_return lexbuf =
    new_line lexbuf;
    STRING "\n" (* to keep the line count correct *)

}

(******************************************************************)
(* Lexer body *)
(******************************************************************)


let white = [' ' '\t']+
let digit = ['0'-'9']
let int = '-'? digit+
let letter = ['a'-'z' 'A'-'Z']
let id = ('_' | letter) ('_' | letter | digit)*

let newline = ('\013'* '\010')
let blank = [' ' '\009' '\012']

let lowercase = ['a'-'z']
let identchar = ['A'-'Z' 'a'-'z' '_' '\'' '0'-'9']
let id = (lowercase | '_') identchar*

rule text = parse
  | "|m" { begin_mode M lexbuf }
  | "|" {end_mode lexbuf}
  | '\n' ('\t')+ { command lexbuf }
  | '\n' { new_line lexbuf; STRING "\n"; end_cmd lexbuf; token lexbuf }
  | "|END" { end_cmd lexbuf }
  | "|" (['a'-'z' 'A'-'Z' '0'-'9' '.' ' ' '_']+ as apply) "->"
      { begin_mode (CMD apply) lexbuf }
  | "|" (['a'-'z' 'A'-'Z' '0'-'9' '.' ' ' '_']+ as apply)
      { begin_mode (CMD apply) lexbuf }
  | ('\n' (' ' | '\t' )* )+ '\n'
      { let s = lexeme lexbuf in
  let l = ref 0 in
  String.iter (fun c -> if c='\n' then (newline lexbuf ; incr l)) s;
        PAR !l }
  | '#' { STRING "\\#" }
  | '_' { STRING "\\_" }
  | '%' { STRING "\\%" }

  | "\\\\" { STRING "\\\\" }
  | "\\{" { STRING "\\{" }
  | "\\}" { STRING "\\}" }
  | "\\$" { STRING "\\$" }
  | "\\\"" { STRING "\"" }
  | "\\&" { STRING "\\&" }
  | "\\ " { STRING "\\ " }
  | "\\'" { STRING "\\'" }
  | "\\`" { STRING "\\`" }

  | '\\' [^ '\\' '{' '}' '$' '"' '&' ' ']
      { lex_error lexbuf "invalid escaping in text mode" }

  | "/*" { start_comment (); comment lexbuf }
  | "//" (_ as c) '\n'
      { start_comment (); Buffer.add_char comment_buf c; end_comment () }
  | '(' { STRING "(" }

  | [^ '"' '$' '{' '<' '\n' '\\' '#' '_' '^' '}' '%' '(']+
      { STRING(lexeme lexbuf) }
  | eof { lex_error lexbuf "unexpected end of file in text mode" }

and comment = parse
  | "*/" { try end_comment () with Exit -> comment lexbuf }
  | "/*" { start_comment (); comment lexbuf }
  | '\n' { newline lexbuf; Buffer.add_char comment_buf '\n'; comment lexbuf }
  | "\\\"" { Buffer.add_char comment_buf '"'; comment lexbuf }
  | (_ as c) { Buffer.add_char comment_buf c; comment lexbuf }
  | eof { lex_error lexbuf "unexpected end of file in comment" }

and math = parse
  | "|t" { begin_mode T lexbuf }
  | "|" {end_mode lexbuf}
  | '\n' ['\t']+ { command lexbuf }
  | '\n' { new_line lexbuf; end_cmd lexbuf; token lexbuf }
  | "|END" { end_cmd lexbuf }

  | '%' { STRING "\\%" }

  | "\\\\" { STRING "\\\\" }
  | "\\{" { STRING "\\{" }
  | "\\}" { STRING "\\}" }
  | "\\$" { STRING "\\$" }
  | "\\\"" { STRING "\"" }
  | "\\&" { STRING "\\&" }
  | "\\ " { STRING "\\ " }
  | "\\_" { STRING "\\_" }

  | '\\' [^ '\\' '{' '}' '$' '"' '&' ' ' '_']
      { lex_error lexbuf "invalid escaping in math mode" }

  | "/*" { start_comment (); comment lexbuf }
  | "//" (_ as c) '\n'
      { start_comment (); Buffer.add_char comment_buf c; end_comment () }
  | '(' { STRING "(" }

  | [^ '"' '$' '{' '\n' '\\' '}' '%' '(']+ { STRING(lexeme lexbuf) }
  | eof { lex_error lexbuf "unexpected end of file in math mode" }

and command = parse
  | "/*" { start_comment (); comment lexbuf }
  | "//" (_ as c) '\n'
      { start_comment (); Buffer.add_char comment_buf c; end_comment () }
  | "|m" { begin_mode M lexbuf }
  | "|t" { begin_mode T lexbuf }
  | "|" {end_mode lexbuf}
  | '\n' ['\t']+ { command lexbuf }
  | '\n' { new_line lexbuf; end_cmd lexbuf; token lexbuf }
  | "|END" { end_cmd lexbuf }
  | '\n' { newline lexbuf; Buffer.add_char comment_buf '\n'; comment lexbuf }
  | "\\\"" { Buffer.add_char comment_buf '"'; comment lexbuf }
  | (_ as c) { Buffer.add_char comment_buf c; comment lexbuf }
  | eof { lex_error lexbuf "unexpected end of file in a command" }

{
  let token lexbuf =
    match get_mode () with
      | M -> math lexbuf
      | T -> text lexbuf
      | CMD -> command lexbuf
}
