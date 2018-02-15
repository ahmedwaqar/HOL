signature tacticToe =
sig
  
  include Abbrev
  
  val set_timeout : real -> unit
  val set_record_hook : (unit -> unit) ref
  val ttt_record : unit -> unit
  
  val init_tactictoe : unit -> unit
  val eval_tactictoe : string -> goal -> unit
  val tactictoe : goal -> tactic 
  val ttt : tactic
  
  val next_tac_glob : tactic list ref
  val next_tac_number : int ref
  val next_tac : goal -> unit 
  val next : int -> tactic

end
