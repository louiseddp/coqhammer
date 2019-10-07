DECLARE PLUGIN "hammer_tactics"

open Ltac_plugin
open Stdarg
open Tacarg
open Names
open Sauto

module Utils = Hhutils

let default_sauto_depth = 5

let get_opt opt def = match opt with Some x -> x | None -> def

let rec destruct_constr t =
  let open Constr in
  let open EConstr in
  match kind Evd.empty t with
  | App(i, args) ->
     begin
       match kind Evd.empty i with
       | Ind(ind, _) when ind = Utils.get_inductive "pair" ->
          begin
            match Array.to_list args with
            | [_; _; t1; t2] ->
               destruct_constr t1 @ destruct_constr t2
            | _ -> [t]
          end
       | _ -> [t]
     end
  | _ -> [t]

let get_s_opts bases unfoldings inverting ctrs =
  let cdefault = Utils.get_constr "Tactics.default" in
  let chints = Utils.get_constr "Tactics.hints" in
  let cnone = Utils.get_constr "Tactics.none" in
  let cnohints = Utils.get_constr "Tactics.nohints" in
  let clogic = Utils.get_constr "Tactics.logic" in
  let to_const t =
    let open Constr in
    let open EConstr in
    match kind Evd.empty t with
    | Const(c, _) -> c
    | _ -> failwith "sauto: not a constant"
  in
  let to_inductive t =
    let open Constr in
    let open EConstr in
    match kind Evd.empty t with
    | Ind(ind, _) -> ind
    | _ -> failwith "sauto: not an inductive type"
  in
  let get_s_opts_field logic_lst conv opts lst default =
    match lst with
    | [h] when h = cdefault -> default
    | [h] when h = chints -> SSome []
    | [h] when h = cnone -> SNone
    | [h] when h = clogic -> SNoHints logic_lst
    | _ ->
       begin
         let b_nohints = List.mem cnohints lst in
         let b_hints = List.mem chints lst in
         let lst = List.filter (fun c -> c <> cnohints && c <> chints) lst in
         let lst = List.map conv lst in
         if b_nohints then
           SNoHints lst
         else if b_hints then
           SSome lst
         else
           match default with
           | SNoHints _ | SNone -> SNoHints lst
           | _ -> SSome lst
       end
  in
  let get_unfoldings opts =
    { opts with s_unfolding =
        get_s_opts_field logic_constants to_const opts
          (destruct_constr unfoldings) default_s_opts.s_unfolding }
  in
  let get_invertings opts =
    { opts with s_inversions =
        get_s_opts_field logic_inductives to_inductive opts
          (destruct_constr inverting) default_s_opts.s_inversions }
  in
  let get_ctrs opts =
    { opts with s_constructors =
        get_s_opts_field logic_inductives to_inductive opts
          (destruct_constr ctrs) default_s_opts.s_constructors }
  in
  let get_bases opts =
    { opts with s_rew_bases = bases }
  in
  get_bases (get_unfoldings (get_invertings (get_ctrs default_s_opts)))

TACTIC EXTEND Hammer_simple_splitting
| [ "simple_splitting" ] -> [ simple_splitting default_s_opts ]
END

TACTIC EXTEND Hammer_sauto_gen_1
| [ "sauto_gen" int_or_var_opt(n) ] -> [ sauto default_s_opts (get_opt n default_sauto_depth) ]
END

TACTIC EXTEND Hammer_ssimpl_gen
| [ "ssimpl_gen" ] -> [
  ssimpl { default_s_opts with s_simpl_tac = Utils.ltac_apply "Tactics.ssolve" [] }
]
END

TACTIC EXTEND Hammer_sauto_gen_2
| [ "sauto_gen" int_or_var_opt(n) "with" ne_preident_list(bases) "using" constr(lemmas) "unfolding" constr(unfoldings)
      "inverting" constr(inverting) "ctrs" constr(ctrs) ] -> [
  if lemmas = Utils.get_constr "Tactics.default" then
    sauto (get_s_opts bases unfoldings inverting ctrs) (get_opt n default_sauto_depth)
  else
    Proofview.tclTHEN
      (Tactics.generalize (destruct_constr lemmas))
      (sauto (get_s_opts bases unfoldings inverting ctrs) (get_opt n default_sauto_depth))
]
END

VERNAC COMMAND EXTEND Hammer_shint_unfold CLASSIFIED AS SIDEFF
| [ "Tactics" "Hint" "Unfold" ident(id) ] -> [
  add_unfold_hint (Utils.get_const (Id.to_string id))
]
END

VERNAC COMMAND EXTEND Hammer_shint_constructors CLASSIFIED AS SIDEFF
| [ "Tactics" "Hint" "Constructors" ident(id) ] -> [
  add_ctrs_hint (Utils.get_inductive (Id.to_string id))
]
END

VERNAC COMMAND EXTEND Hammer_shint_rewrite CLASSIFIED AS SIDEFF
| [ "Tactics" "Hint" "Inversion" ident(id) ] -> [
  add_inversion_hint (Utils.get_inductive (Id.to_string id))
]
END
