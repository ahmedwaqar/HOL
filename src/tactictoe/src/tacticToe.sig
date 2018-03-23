signature tacticToe =
sig

  include Abbrev

  (* TacticToe *)
  val ttt       : tactic
  val tactictoe : term -> tactic

  (* Settings *)
  val set_timeout : real -> unit

  (* Step by step exploration *)
  val next_tac : goal -> unit
  val next     : int -> tactic

  (* Recording *)
  val ttt_record        : unit -> unit
  val ttt_record_sigobj : unit -> unit
  val ttt_clean_all     : unit -> unit

  (* Evaluation *)
  val ttt_eval_thy : string -> unit
  val eprover_eval_thy : string -> unit

end
