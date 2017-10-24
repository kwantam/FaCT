open Pos
open Err
open Tast

#define err(p) InternalCompilerError("from source" ^ __LOC__ << p)

(* x for 'eXtract' *)
let xwrap f pa = f pa.pos pa.data
#define xfunction xwrap @@ fun p -> function

let gh_bty = xfunction
  | UInt n -> Printf.sprintf "uint%d_t" n
  | Int  n -> Printf.sprintf  "int%d_t" n
  | Bool   -> Printf.sprintf  "uint8_t" (* XXX *)
  | Num  _ -> raise @@ err(p)

let gh_label' p = function
  | Public -> "/*public*/"
  | Secret -> "/*secret*/"
  | Unknown -> raise @@ err(p)

let gh_label = xfunction
  | Fixed l -> gh_label' p l
  | Guess _ -> raise @@ err(p)

let gh_mut = xfunction
  | Const -> ""
  | Mut -> "*"

let gh_amut = xfunction
  | Const -> "const "
  | Mut -> ""

let gh_lexpr = xfunction
  | LIntLiteral n -> string_of_int n
  | LDynamic _ -> ""

let gh_aty = xfunction
  | ArrayAT(b,lexpr) -> Printf.sprintf "%s[%s]" (gh_bty b) (gh_lexpr lexpr)

let gh_ety = xfunction
  | BaseET(b,l) -> String.concat "\n" [gh_label l; gh_bty b]
  | ArrayET _ -> raise @@ err(p)

let gh_vty = xfunction
  | RefVT(b,l,m) -> Printf.sprintf "%s %s%s" (gh_label l) (gh_bty b) (gh_mut m)
  | ArrayVT(a,l,m) -> Printf.sprintf "%s %s%s" (gh_label l) (gh_amut m) (gh_aty a)

let gh_rty = function
  | None -> "void"
  | Some ety -> gh_ety ety

let gh_param { data=Param(x,vty) } =
  "\n  " ^ gh_vty vty ^ " " ^ x.data

let gh_fdec = xfunction
  | FunDec(f,rt,params,_) ->
    let paramdecs = String.concat "," @@ List.map gh_param params in
      Printf.sprintf
        "%s %s(%s);"
        (gh_rty rt)
        f.data
        paramdecs
  | _ -> ""

let gh_module (Module(fenv,fdecs)) =
  String.concat "\n\n" @@ List.map gh_fdec fdecs

let generate_header fname m =
  let header_name = fname
                    |> Filename.basename
                    |> String.uppercase_ascii in
    Printf.sprintf
"#ifndef __%s_H
#define __%s_H

%s

#endif /* __%s_H */"
      header_name
      header_name
      (gh_module m)
      header_name