(*---------------------------------------------------------------------------
                An ML script for building HOL
 ---------------------------------------------------------------------------*)

fun normPath s = Path.toString(Path.fromString s)
fun itstrings f [] = raise Fail "itstrings: empty list"
  | itstrings f [x] = x
  | itstrings f (h::t) = f h (itstrings f t);
fun fullPath slist = normPath
   (itstrings (fn chunk => fn path => Path.concat (chunk,path)) slist);

fun quote s = String.concat["\"", s, "\""];

(*---------------------------------------------------------------------------
     The following lines are written at configuration time.
 ---------------------------------------------------------------------------*)

val OS = Systeml.OS;
val HOLDIR = Systeml.HOLDIR
val EXECUTABLE = Systeml.xable_string (fullPath [HOLDIR, "bin", "build"])
val DEPDIR = Systeml.DEPDIR
val GNUMAKE = Systeml.GNUMAKE

(*---------------------------------------------------------------------------
     Source directories.
 ---------------------------------------------------------------------------*)

val SRCDIRS0 =
 ["src/portableML", "src/0", "src/parse", "src/bool", "src/goalstack",
  "src/taut", "src/compute/src", "src/q", "src/combin", "src/marker",
  "src/labels", "src/lite", "src/refute", "src/simp/src", "src/metis",
  "src/meson/src","src/basicProof", "src/relation", "src/pair/src",
  "src/sum", "src/one", "src/option", "src/num/theories",
  "src/num/reduce/src", "src/num/arith/src","src/num", "src/IndDef",
  "src/datatype/parse", "src/datatype/equiv", "src/datatype/record",
  "src/datatype", "src/list/src", "src/tfl/src", "src/Boolify/src",
  "src/unwind", "src/boss", "src/word32", "src/string", "src/llist",
  "src/pred_set/src", "src/path", "src/ring/src", "src/integer",
  "src/res_quan/src", "src/word/theories", "src/word/src",
  "src/finite_map", "src/hol88", "src/real", "src/bag",
  "src/temporal/src", "src/temporal/smv.2.4.3", "src/prob",
  "src/HolSat", "src/muddy/muddyC", "src/muddy", "src/HolBdd"];

val SRCDIRS = map (fn s => fullPath [HOLDIR, s]) SRCDIRS0



val SIGOBJ = fullPath [HOLDIR, "sigobj"];
val HOLMAKE = fullPath [HOLDIR, "bin/Holmake"]

open Systeml;
val SYSTEML = Systeml.systeml

fun Holmake dir =
  if SYSTEML [HOLMAKE, "--qof"] = Process.success then ()
  else (print ("Build failed in directory "^dir^"\n");
        raise Fail "Couldn't make directory");


fun Gnumake dir =
  if SYSTEML [GNUMAKE] = Process.success then ()
  else (print ("Build failed in directory "^dir
                ^" ("^GNUMAKE^" failed).\n");
        raise Fail "Couldn't make directory");

(* ----------------------------------------------------------------------
   Some useful file-system utility functions
   ---------------------------------------------------------------------- *)

fun map_dir f dir =  (* map a function over the files in a directory *)
  let val dstrm = FileSys.openDir dir
      fun loop() =
        case FileSys.readDir dstrm
         of NONE => FileSys.closeDir dstrm
          | SOME file => (f (dir,file) ; loop())
  in loop()
  end handle OS.SysErr(s, erropt) =>
    (print ("OS error: "^s^" - "^
            (case erropt of SOME s' => OS.errorMsg s' | _ => "") ^ "\n");
     Process.exit Process.failure);


fun copy file path =  (* Dead simple file copy *)
 let open TextIO
     val (istrm,ostrm) = (openIn file, openOut path)
     fun loop() =
       case input1 istrm
        of SOME ch => (output1(ostrm,ch) ; loop())
         | NONE    => (closeIn istrm; flushOut ostrm; closeOut ostrm)
  in loop()
  end;

fun bincopy file path =  (* Dead simple file copy - binary version *)
 let open BinIO
     val (istrm,ostrm) = (openIn file, openOut path)
     fun loop() =
       case input1 istrm
        of SOME ch => (output1(ostrm,ch) ; loop())
         | NONE    => (closeIn istrm; flushOut ostrm; closeOut ostrm)
  in loop()
  end;


fun link b s1 s2 =
  let open Process
  in if SYSTEML ["ln", "-s", s1, s2] = success then ()
     else (print ("Unable to link file "^quote s1^" to file "^quote s2^".\n");
           raise Fail "link")
  end

(* f is either bincopy or copy *)
fun update_copy f src dest = let
  val t0 = FileSys.modTime src
in
  f src dest;
  FileSys.setTime(dest, SOME t0)
end
fun cp b = if b then update_copy bincopy else update_copy copy

fun mv0 s1 s2 = let
  val s1' = normPath s1
  val s2' = normPath s2
in
  FileSys.rename{old=s1', new=s2'}
end

fun mv b = if b then mv0 else cp b

(* uploadfn is of type : bool -> string -> string -> unit
     the boolean is whether or not the arguments are binary files
     the strings are source and destination file-names, in that order
*)
fun transfer_file uploadfn targetdir (df as (dir,file)) = let
  fun transfer binaryp (dir,file1,file2) =
    uploadfn binaryp (fullPath [dir,file1]) (fullPath [targetdir,file2])
  fun idtransfer binaryp (dir,file) = transfer binaryp (dir,file,file)
  fun digest_sig file =
      let val b = Path.base file
      in if (String.extract(b,String.size b -4,NONE) = "-sig"
             handle _ => false)
         then SOME (String.extract(b,0,SOME (String.size b - 4)))
         else NONE
      end
  fun augmentSRCFILES file = let
    open TextIO
    val ostrm = openAppend (Path.concat(SIGOBJ,"SRCFILES"))
  in
    output(ostrm,fullPath[dir,file]^"\n") ;
    closeOut ostrm
  end

in
  case Path.ext file of
    SOME"ui"     => idtransfer true df
  | SOME"uo"     => idtransfer true df
  | SOME"so"     => idtransfer true df   (* for dynlibs *)
  | SOME"xable"  => idtransfer true df   (* for executables *)
  | SOME"sig"    => (idtransfer false df; augmentSRCFILES (Path.base file))
  | SOME"sml"    => (case digest_sig file of
                       NONE => ()
                     | SOME file' =>
                       (transfer false (dir,file, file' ^".sig");
                        augmentSRCFILES file'))
  |    _         => ()
end;


(*---------------------------------------------------------------------------
           Compile a HOL directory in place. Some libraries,
           e.g., the robdd libraries, need special treatment because
           they come with external tools or C libraries.
 ---------------------------------------------------------------------------*)

fun build_dir dir = let
  val _ = FileSys.chDir dir
  val _ = print ("Working in directory "^dir^"\n")
in
  case #file(Path.splitDirFile dir) of
    "muddyC" =>
      (case OS
        of "winNT" =>
             bincopy (fullPath [HOLDIR, "tools", "win-binaries", "muddy.so"])
                     (fullPath [HOLDIR, "sigobj", "muddy.so"])
         | other => Gnumake dir handle _ =>
                           print(String.concat
                                 ["\nmuddyLib has NOT been built!! ",
                                  "(continuing anyway).\n\n"]))
  | "smv.2.4.3" => (Gnumake dir
                    handle _ => print(String.concat
                                      ["\nCompilation of SMV fails!!",
                                       " temporal Lib has NOT been built!! ",
                                       "(continuing anyway).\n\n"]))
  | _ => Holmake dir
end
handle OS.SysErr(s, erropt) =>
  (print ("OS error: "^s^" - "^
          (case erropt of SOME s' => OS.errorMsg s' | _ => "") ^ "\n");
   Process.exit Process.failure);


(*---------------------------------------------------------------------------
        Transport a compiled directory to another location. The
        symlink argument says whether this is via a symbolic link,
        or by copying. The ".uo", ".ui", ".so", ".xable" and ".sig"
        files are transported.
 ---------------------------------------------------------------------------*)

fun upload (src,target,symlink) =
  (print ("Uploading files to "^target^"\n");
   map_dir (transfer_file symlink target) src)
        handle OS.SysErr(s, erropt) =>
          (print ("OS error: "^s^" - "^
                  (case erropt of SOME s' => OS.errorMsg s' | _ => "") ^ "\n");
           Process.exit Process.failure)


(*---------------------------------------------------------------------------
    For each element in SRCDIRS, build it, then upload it to SIGOBJ.
    This allows us to have the build process only occur w.r.t. SIGOBJ
    (thus requiring only a single place to look for things).
 ---------------------------------------------------------------------------*)

fun buildDir symlink s = (build_dir s; upload(s,SIGOBJ,symlink));

fun build_src symlink = List.app (buildDir symlink) SRCDIRS;

fun rem_file f =
 FileSys.remove f
   handle _ => (print ("Trouble with removing file "^f^"?\n"); ());


fun clean_sigobj() = let
  val _ = print ("Cleaning out "^SIGOBJ^"\n")
  (* need to avoid removing the systeml stuff that will have been put into
     sigobj by the action of configure.sml *)
  val lowcase = String.map Char.toLower
  fun sigobj_rem_file s = let
    val f = Path.file s
    val n = lowcase (hd (String.fields (fn c => c = #".") f))
  in
    if List.exists (fn x => x = n) ["systeml", "cvs", "", "readme"] then ()
    else rem_file s
  end
  fun write_initial_srcfiles () = let
    val outstr = TextIO.openOut (fullPath [HOLDIR, "sigobj", "SRCFILES"])
  in
    TextIO.output(outstr, fullPath [HOLDIR, "tools", "Holmake", "Systeml"]);
    TextIO.output(outstr, "\n");
    TextIO.closeOut(outstr)
  end
in
  map_dir (sigobj_rem_file o normPath o Path.concat) SIGOBJ;
  write_initial_srcfiles ()
end;

fun build_adoc_files () = let
  val docdirs = let
    val instr = TextIO.openIn(fullPath [HOLDIR, "tools",
                                        "documentation-directories"])
    val wholefile = TextIO.inputAll instr before TextIO.closeIn instr
  in
    map normPath (String.tokens Char.isSpace wholefile)
  end handle _ => (print "Couldn't read documentation directories file\n";
                   [])
  val doc2txt = fullPath [HOLDIR, "help", "src", "Doc2Txt"]
  fun make_adocs dir = let
    val fulldir = fullPath [HOLDIR, dir]
  in
    if SYSTEML [doc2txt, fulldir, fulldir] = Process.success then true
    else
      (print ("Generation of ASCII doc files failed in directory "^dir^"\n");
       false)
  end
in
  List.all make_adocs docdirs
end




fun build_help () =
 let val dir = Path.concat(Path.concat (HOLDIR,"help"),"src")
     val _ = FileSys.chDir dir
     val _ = build_dir dir
     val doc2html = fullPath [dir,"Doc2Html"]
     val docpath  = fullPath [HOLDIR, "help", "Docfiles"]
     val htmlpath = fullPath [docpath, "HTML"]
     val _        = if (FileSys.isDir htmlpath handle _ => false) then ()
                    else (print ("Creating directory "^htmlpath^"\n");
                          FileSys.mkDir htmlpath)
     val cmd1     = [doc2html, docpath, htmlpath]
     val cmd2     = [fullPath [dir,"makebase"]]
     val _ = print "Generating ASCII versions of Docfiles...\n"
     val _ = if build_adoc_files () then print "...ASCII Docfiles done\n"
             else ()
 in
   print "Generating HTML versions of Docfiles...\n"
 ;
   if SYSTEML cmd1  = Process.success then print "...HTML Docfiles done\n"
   else (print ("Build failed in directory "^dir^"\n");
         raise Fail "Couldn't make html versions of Docfiles")
 ;
   if (print "Building Help DB\n"; SYSTEML cmd2) = Process.success then ()
   else (print ("Build failed in directory "^dir^"\n");
        raise Fail "Couldn't make help database")
 end;

fun make_buildstamp () =
 let open Path TextIO
     val stamp_filename = concat(HOLDIR, concat("tools","build-stamp"))
     val stamp_stream = openOut stamp_filename
     val date_string = Date.toString (Date.fromTimeLocal (Time.now()))
 in
    output(stamp_stream, " (built "^date_string^")");
    closeOut stamp_stream
end


fun build_hol symlink =
  let val _ = clean_sigobj()
      val _ = build_src symlink
      val _ = make_buildstamp()
      val _ = build_help()
  in
    print "\nHol built successfully.\n"
  end;


(*---------------------------------------------------------------------------
       Get rid of compiled code and dependency information.
 ---------------------------------------------------------------------------*)

local val lenScript = String.size "Script"
      val lenTheory_ext = String.size "Theory.sig"
in
fun suffixCheck s =
 let val len = String.size s
 in (("Script" = String.extract(s,len-lenScript,NONE)) orelse raise Subscript)
    handle Subscript
    =>  let val suffix = String.extract(s,len - lenTheory_ext, NONE)
        in (len > 10
            andalso ((suffix = "Theory.sig") orelse (suffix = "Theory.sml")))
           orelse raise Subscript
         end
        handle Subscript => false
  end
end;

(*---------------------------------------------------------------------------
    "cleandir" could be extended to do a better job of cleaning up
    directories where external tools have been built.
 ---------------------------------------------------------------------------*)

fun cleandir dir =
  let fun efile s =
        case Path.ext s
         of SOME "ui" => true
          | SOME "uo" => true
          | SOME "so" => true         (* for dynlibs, like muddyLib *)
          | SOME "o"  => true         (* for C libraries *)
          | SOME "xable"  => true     (* for executables *)
          |    _          => suffixCheck s
      fun del (d,f) = if efile f then rem_file (fullPath [d,f]) else ()
  in
    map_dir del dir
  end;

fun cleanAlldir dir = (* clean directory d and also remove d/DEPDIR *)
  let val _ = cleandir dir
      val depdir = Path.concat(dir,DEPDIR)
  in
    if (FileSys.isDir depdir handle _ => false)
    then (map_dir (rem_file o normPath o Path.concat) depdir;
          FileSys.rmDir depdir handle e
           => (print ("Unable to remove directory "^depdir^".\n"); ()))
    else ()
  end;

fun clean_dirs f = clean_sigobj() before List.app f SRCDIRS;

fun errmsg s = TextIO.output(TextIO.stdErr, s ^ "\n");
val help_mesg = "Usage: build\n\
                \   or: build -symlink\n\
                \   or: build -small\n\
                \   or: build -dir <fullpath>\n\
                \   or: build -dir <fullpath> -symlink\n\
                \   or: build -clean\n\
                \   or: build -cleanAll\n\
                \   or: build symlink\n\
                \   or: build small\n\
                \   or: build clean\n\
                \   or: build cleanAll\n\
                \   or: build help.";

fun check_against s = let
  open Time
  val cfgtime = FileSys.modTime (fullPath [HOLDIR, s])
in
  if FileSys.modTime EXECUTABLE < cfgtime then
    (print ("WARNING! WARNING!\n");
     print ("  The build file is older than " ^ s ^ ";\n");
     print ("  this suggests you should reconfigure the system.\n");
     print ("  Press Ctl-C now to abort the build; <RETURN> to continue.\n");
     print ("WARNING! WARNING!\n");
     ignore (TextIO.inputLine TextIO.stdIn))
  else ()
end;

val _ = check_against "tools/configure.sml"
val _ = check_against "tools/build.sml"
val _ = check_against "tools/Holmake/Systeml.sig"

fun symlink_check() =
    if OS = "winNT" then
      (print "Sorry; symbolic linking isn't available under Windows NT";
       Process.exit Process.failure)
    else link

val _ =
  case Mosml.argv ()
   of [_]             => build_hol cp                (* no symbolic linking *)
    | [_,"-symlink"]  => build_hol (symlink_check()) (* w/ symbolic linking *)
    | [_,"-small"]    => build_hol mv                (* by renaming *)
    | [_,"-dir",path] => buildDir cp path
    | [_,"-dir",path,
         "-symlink"]  => buildDir link path
    | [_,"-clean"]    => clean_dirs cleandir
    | [_,"-cleanAll"] => clean_dirs cleanAlldir
    | [_,"clean"]     => clean_dirs cleandir
    | [_,"cleanAll"]  => clean_dirs cleanAlldir
    | [_,"symlink"]   => build_hol (symlink_check())
    | [_,"small"]     => build_hol mv
    | [_,"help"]      => build_help()
    | otherwise       => errmsg help_mesg
