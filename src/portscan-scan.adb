--  This file is covered by the Internet Software Consortium (ISC) License
--  Reference: ../License.txt

with Ada.Characters.Latin_1;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Calendar;
with File_Operations;
with Port_Specification.Transform;
with Port_Specification.Json;
with Port_Specification.Web;
with Specification_Parser;
with PortScan.Log;
with PortScan.Operations;
with Parameters;
with Utilities;
with Replicant;
with Signals;
with Unix;

package body PortScan.Scan is

   package UTL renames Utilities;
   package REP renames Replicant;
   package PM  renames Parameters;
   package LOG renames PortScan.Log;
   package OPS renames PortScan.Operations;
   package FOP renames File_Operations;
   package PAR renames Specification_Parser;
   package PST renames Port_Specification.Transform;
   package WEB renames Port_Specification.Web;
   package PSP renames Port_Specification;
   package LAT renames Ada.Characters.Latin_1;
   package DIR renames Ada.Directories;
   package EX  renames Ada.Exceptions;

   --------------------------------------------------------------------------------------------
   --  scan_entire_ports_tree
   --------------------------------------------------------------------------------------------
   function scan_entire_ports_tree (sysrootver : sysroot_characteristics) return Boolean
   is
      good_scan    : Boolean;
      using_screen : constant Boolean := Unix.screen_attached;
      conspiracy   : constant String := HT.USS (PM.configuration.dir_conspiracy);
      unkindness   : constant String := HT.USS (PM.configuration.dir_unkindness);
   begin
      --  Override BATCH_MODE setting when we build everything
      PM.configuration.batch_mode := True;

      --  All scanning done on host system (no need to mount in a slave)
      prescan_ports_tree (conspiracy, unkindness, sysrootver);
      prescan_unkindness (unkindness);
      set_portlist_to_everything;
      LOG.set_scan_start_time (CAL.Clock);
      parallel_deep_scan (conspiracy    => conspiracy,
                          unkindness    => unkindness,
                          sysrootver    => sysrootver,
                          success       => good_scan,
                          show_progress => using_screen);
      LOG.set_scan_complete (CAL.Clock);

      return good_scan;
   end scan_entire_ports_tree;


   --------------------------------------------------------------------------------------------
   --  generate_entire_website
   --------------------------------------------------------------------------------------------
   function generate_entire_website
     (www_site   : String;
      sysrootver : sysroot_characteristics) return Boolean
   is
      good_operation : Boolean;
      conspiracy     : constant String := HT.USS (PM.configuration.dir_conspiracy);
      unkindness     : constant String := HT.USS (PM.configuration.dir_unkindness);
      sharedir       : constant String := host_localbase & "/share/ravenadm";
      ravencss       : constant String := "/ravenports.css";
      ravenboxpng    : constant String := "/ravenports-200.png";
      styledir       : constant String := www_site & "/style";
   begin
      --  Override BATCH_MODE setting when we build everything
      PM.configuration.batch_mode := True;

      --  All scanning done on host system (no need to mount in a slave)
      prescan_ports_tree (conspiracy, unkindness, sysrootver);
      prescan_unkindness (unkindness);

      --  pre-place css file
      DIR.Create_Path (styledir);
      DIR.Copy_File (sharedir & ravencss, styledir & ravencss);
      DIR.Copy_File (sharedir & ravenboxpng, styledir & ravenboxpng);

      --  subcontract web site generation
      serially_generate_web_pages (www_site   => www_site,
                                   sysrootver => sysrootver,
                                   success    => good_operation);
      return good_operation;
   end generate_entire_website;


   --------------------------------------------------------------------------------------------
   --  prescan_ports_tree
   --------------------------------------------------------------------------------------------
   procedure prescan_ports_tree
     (conspiracy : String;
      unkindness : String;
      sysrootver : sysroot_characteristics)
   is
      conspindex_path : constant String := conspiracy & conspindex;
      custom_avail    : constant Boolean := unkindness /= PM.no_unkindness;
      --  Disable parallel scanning (not reliable; make one scanner do everything
      --  max_lots    : constant scanners := get_max_lots;
      max_lots        : constant scanners := 1;
   begin
      if not DIR.Exists (conspindex_path) then
         raise missing_index with conspindex;
      end if;

      declare
         fulldata  : String := FOP.get_file_contents (conspindex_path);
         markers   : HT.Line_Markers;
         linenum   : Natural := 0;
      begin
         HT.initialize_markers (fulldata, markers);
         loop
            exit when not HT.next_line_present (fulldata, markers);
            linenum := linenum + 1;
            declare
               line     : constant String := HT.extract_line (fulldata, markers);
               bucket   : constant String := HT.specific_field (line, 1);
               namebase : constant String := HT.specific_field (line, 2);
               numvar   : constant String := HT.specific_field (line, 3);
               bsheet   : constant String := "/bucket_" & bucket & "/" & namebase;
               linestr  : constant String := ", line " & HT.int2str (linenum);
               varcount : Integer;
            begin
               if bucket'Length /= 2 or else namebase'Length = 0 or else numvar'Length = 0 then
                  raise bad_index_data with conspindex & linestr;
               end if;
               begin
                  varcount := Integer'Value (numvar);
               exception
                  when others =>
                     raise bad_index_data
                       with conspindex & ", numvariant fields not an integer" & linestr;
               end;
               if not DIR.Exists (conspiracy & bsheet) then
                  raise bad_index_data
                    with conspindex & bsheet & " buildsheet does not exist" & linestr;
               end if;
               if custom_avail and then DIR.Exists (unkindness & bsheet) then
                  --  postpone custom port scan (done prescan_unkindness)
                  null;
               else
                  for varx in Integer range 1 .. varcount loop
                     declare
                        varxname : constant String := HT.specific_field (line, varx + 3);
                        portkey  : HT.Text := HT.SUS (namebase & ":" & varxname);
                        kc       : portkey_crate.Cursor;
                        success  : Boolean;
                     begin
                        if varxname = "" then
                           raise bad_index_data
                             with conspindex & ", less variants than counter" & linestr;
                        end if;
                        ports_keys.Insert (Key      => portkey,
                                           New_Item => lot_counter,
                                           Position => kc,
                                           Inserted => success);
                        last_port := lot_counter;
                        all_ports (lot_counter).sequence_id   := lot_counter;
                        all_ports (lot_counter).key_cursor    := kc;
                        all_ports (lot_counter).port_namebase := HT.SUS (namebase);
                        all_ports (lot_counter).port_variant  := HT.SUS (varxname);
                        all_ports (lot_counter).bucket        := bucket_code (bucket);
                        all_ports (lot_counter).unkind_custom := False;

                        make_queue (lot_number).Append (lot_counter);
                        lot_counter := lot_counter + 1;
                        if lot_number = max_lots then
                           lot_number := 1;
                        else
                           lot_number := lot_number + 1;
                        end if;
                     end;
                  end loop;
               end if;
            end;
         end loop;
      end;

      prescanned := True;
   end prescan_ports_tree;


   --------------------------------------------------------------------------------------------
   --  prescan_custom
   --------------------------------------------------------------------------------------------
   procedure prescan_custom
     (unkindness    : String;
      bucket        : bucket_code;
      namebase      : String;
      max_lots      : scanners)
   is
      --  Assume buildsheet exists (has already been validated)
      --  Assume it starts with directory separator
      successful : Boolean;
      customspec : PSP.Portspecs;
      arch_focus : supported_arch := x86_64;  -- unused, pick one
      buildsheet : constant String := "/bucket_" & bucket & "/" & namebase;
   begin
      PAR.parse_specification_file (dossier         => unkindness & buildsheet,
                                    specification   => customspec,
                                    opsys_focus     => platform_type,
                                    arch_focus      => arch_focus,
                                    success         => successful,
                                    stop_at_targets => True);
      if not successful then
         raise bsheet_parsing
           with unkindness & buildsheet & "-> " & PAR.get_parse_error;
      end if;
      declare
         varcount : Natural := customspec.get_number_of_variants;
         varlist  : String  := customspec.get_field_value (PSP.sp_variants);
      begin
         for varx in Integer range 1 .. varcount loop
            declare
               varxname : constant String := HT.specific_field (varlist, varx, ", ");
               portkey  : HT.Text := HT.SUS (namebase & ":" & varxname);
               kc       : portkey_crate.Cursor;
               success  : Boolean;
               use type portkey_crate.Cursor;
            begin
               if ports_keys.Contains (portkey) then
                  kc := ports_keys.Find (portkey);
                  for x in 1 .. last_port loop
                     if all_ports (x).key_cursor = kc then
                        all_ports (x).unkind_custom := True;
                        exit;
                     end if;
                  end loop;
               else
                  ports_keys.Insert (Key      => portkey,
                                     New_Item => lot_counter,
                                     Position => kc,
                                     Inserted => success);
                  last_port := lot_counter;
                  all_ports (lot_counter).sequence_id   := lot_counter;
                  all_ports (lot_counter).key_cursor    := kc;
                  all_ports (lot_counter).port_namebase := HT.SUS (namebase);
                  all_ports (lot_counter).port_variant  := HT.SUS (varxname);
                  all_ports (lot_counter).bucket        := bucket;
                  all_ports (lot_counter).unkind_custom := True;

                  make_queue (lot_number).Append (lot_counter);
                  lot_counter := lot_counter + 1;
                  if lot_number = max_lots then
                     lot_number := 1;
                  else
                     lot_number := lot_number + 1;
                  end if;
               end if;
            end;
         end loop;
      end;
   end prescan_custom;


   --------------------------------------------------------------------------------------------
   --  prescan_unkindness
   --------------------------------------------------------------------------------------------
   procedure prescan_unkindness (unkindness : String)
   is
      --  Disable parallel scanning (not reliable; make one scanner do everything
      --  max_lots : constant scanners := get_max_lots;
      max_lots : constant scanners := 1;
      bucket   : bucket_code;
   begin
      if unkindness = PM.no_unkindness or else
        not DIR.Exists (unkindness)
      then
         return;
      end if;

      for highdigit in AF'Range loop
         for lowdigit in AF'Range loop
            bucket := tohex (highdigit) & tohex (lowdigit);
            declare
               bucket_dir   : constant String := unkindness & "/bucket_" & bucket;
               Inner_Search : DIR.Search_Type;
               Inner_Dirent : DIR.Directory_Entry_Type;
               use type DIR.File_Kind;
            begin
               if DIR.Exists (bucket_dir) and then
                 DIR.Kind (bucket_dir) = DIR.Directory
               then

                  DIR.Start_Search (Search    => Inner_Search,
                                    Directory => bucket_dir,
                                    Filter    => (DIR.Ordinary_File => True, others => False),
                                    Pattern   => "*");

                  while DIR.More_Entries (Inner_Search) loop
                     DIR.Get_Next_Entry (Inner_Search, Inner_Dirent);
                     declare
                        namebase : String := DIR.Simple_Name (Inner_Dirent);
                     begin
                        prescan_custom (unkindness => unkindness,
                                        bucket     => bucket,
                                        namebase   => namebase,
                                        max_lots   => max_lots);
                     end;
                  end loop;
                  DIR.End_Search (Inner_Search);
               end if;
            end;
         end loop;
      end loop;
   end prescan_unkindness;


   --------------------------------------------------------------------------------------------
   --  set_portlist_to_everything
   --------------------------------------------------------------------------------------------
   procedure set_portlist_to_everything is
   begin
      for x in 0 .. last_port loop
         declare
            portkey : String := get_port_variant (all_ports (x));
         begin
            if not HT.equivalent (all_ports (x).port_namebase, default_compiler) then
               portlist.Append (HT.SUS (portkey));
            end if;
         end;
      end loop;
   end set_portlist_to_everything;


   --------------------------------------------------------------------------------------------
   --  get_max_lots
   --------------------------------------------------------------------------------------------
   function get_max_lots return scanners
   is
      first_try : constant Positive := Positive (PM.configuration.number_cores) * 3;
   begin
      if first_try > Positive (scanners'Last) then
         return scanners'Last;
      else
         return scanners (first_try);
      end if;
   end get_max_lots;


   --------------------------------------------------------------------------------------------
   --  parallel_deep_scan
   --------------------------------------------------------------------------------------------
   procedure parallel_deep_scan
     (conspiracy    : String;
      unkindness    : String;
      sysrootver    : sysroot_characteristics;
      success       : out Boolean;
      show_progress : Boolean)
   is
      finished : array (scanners) of Boolean := (others => False);
      combined_wait : Boolean := True;
      aborted : Boolean := False;

      task type scan (lot : scanners);
      task body scan
      is
         procedure populate (cursor : subqueue.Cursor);
         procedure populate (cursor : subqueue.Cursor)
         is
            target_port : port_index := subqueue.Element (cursor);
         begin
            if not aborted then
               populate_port_data (conspiracy   => conspiracy,
                                   unkindness   => unkindness,
                                   target       => target_port,
                                   always_build => False,
                                   sysrootver   => sysrootver);
               mq_progress (lot) := mq_progress (lot) + 1;
            end if;
         exception
            when issue : others =>
               aborted := True;
               TIO.Put_Line ("Scan aborted");
               TIO.Put_Line ("culprit: " & get_port_variant (all_ports (target_port)));
               TIO.Put_Line (EX.Exception_Information (issue));
         end populate;
      begin
         make_queue (lot).Iterate (populate'Access);
         finished (lot) := True;
      end scan;

      scan_01 : scan (lot => 1);
      scan_02 : scan (lot => 2);
      scan_03 : scan (lot => 3);
      scan_04 : scan (lot => 4);
      scan_05 : scan (lot => 5);
      scan_06 : scan (lot => 6);
      scan_07 : scan (lot => 7);
      scan_08 : scan (lot => 8);
      scan_09 : scan (lot => 9);
      scan_10 : scan (lot => 10);
      scan_11 : scan (lot => 11);
      scan_12 : scan (lot => 12);
      scan_13 : scan (lot => 13);
      scan_14 : scan (lot => 14);
      scan_15 : scan (lot => 15);
      scan_16 : scan (lot => 16);
      scan_17 : scan (lot => 17);
      scan_18 : scan (lot => 18);
      scan_19 : scan (lot => 19);
      scan_20 : scan (lot => 20);
      scan_21 : scan (lot => 21);
      scan_22 : scan (lot => 22);
      scan_23 : scan (lot => 23);
      scan_24 : scan (lot => 24);
      scan_25 : scan (lot => 25);
      scan_26 : scan (lot => 26);
      scan_27 : scan (lot => 27);
      scan_28 : scan (lot => 28);
      scan_29 : scan (lot => 29);
      scan_30 : scan (lot => 30);
      scan_31 : scan (lot => 31);
      scan_32 : scan (lot => 32);

   begin
      TIO.Put_Line ("Scanning entire ports tree.");
      while combined_wait loop
         delay 1.0;
         if show_progress then
            TIO.Put (scan_progress);
         end if;
         combined_wait := False;
         for j in scanners'Range loop
            if not finished (j) then
               combined_wait := True;
               exit;
            end if;
         end loop;
         if Signals.graceful_shutdown_requested then
            aborted := True;
         end if;
      end loop;
      success := not aborted;
   end parallel_deep_scan;


   --------------------------------------------------------------------------------------------
   --  skeleton_compiler_data
   --------------------------------------------------------------------------------------------
   procedure skeleton_compiler_data
     (conspiracy    : String;
      unkindness    : String;
      target        : port_index;
      sysrootver    : sysroot_characteristics)
   is
      rec : port_record renames all_ports (target);
      function calc_dossier return String;

      thespec    : PSP.Portspecs;
      successful : Boolean;
      variant    : constant String := HT.USS (rec.port_variant);
      osrelease  : constant String := HT.USS (sysrootver.release);

      function calc_dossier return String
      is
         buildsheet : String := "/bucket_" & rec.bucket & "/" & HT.USS (rec.port_namebase);
      begin
         if rec.unkind_custom then
            return unkindness & buildsheet;
         else
            return conspiracy & buildsheet;
         end if;
      end calc_dossier;
   begin
      OPS.parse_and_transform_buildsheet (specification => thespec,
                                          successful    => successful,
                                          buildsheet    => calc_dossier,
                                          variant       => variant,
                                          portloc       => "",
                                          excl_targets  => True,
                                          avoid_dialog  => True,
                                          for_webpage   => False,
                                          sysrootver    => sysrootver);
      if not successful then
         raise bsheet_parsing
           with calc_dossier & "-> " & PAR.get_parse_error;
      end if;

      rec.pkgversion    := HT.SUS (thespec.calculate_pkgversion);
      rec.ignore_reason := HT.SUS (thespec.aggregated_ignore_reason);
      rec.ignored       := not HT.IsBlank (rec.ignore_reason);
      rec.scanned       := False;

      for item in Positive range 1 .. thespec.get_subpackage_length (variant) loop
         declare
            newrec     : subpackage_record;
            subpackage : String := thespec.get_subpackage_item (variant, item);
         begin
            newrec.subpackage   := HT.SUS (subpackage);
            newrec.never_remote := True;
            newrec.pkg_present  := True;
            rec.subpackages.Append (newrec);
         end;
      end loop;

   end skeleton_compiler_data;



   --------------------------------------------------------------------------------------------
   --  populate_port_data
   --------------------------------------------------------------------------------------------
   procedure populate_port_data
     (conspiracy    : String;
      unkindness    : String;
      target        : port_index;
      always_build  : Boolean;
      sysrootver    : sysroot_characteristics)
   is
      rec : port_record renames all_ports (target);
      function calc_dossier return String;

      thespec    : PSP.Portspecs;
      successful : Boolean;
      variant    : constant String := HT.USS (rec.port_variant);
      osrelease  : constant String := HT.USS (sysrootver.release);
      prime_pkg  : HT.Text := HT.blank;

      function calc_dossier return String
      is
         buildsheet : String := "/bucket_" & rec.bucket & "/" & HT.USS (rec.port_namebase);
      begin
         if rec.unkind_custom then
            return unkindness & buildsheet;
         else
            return conspiracy & buildsheet;
         end if;
      end calc_dossier;
   begin
      OPS.parse_and_transform_buildsheet (specification => thespec,
                                          successful    => successful,
                                          buildsheet    => calc_dossier,
                                          variant       => variant,
                                          portloc       => "",
                                          excl_targets  => True,
                                          avoid_dialog  => False,
                                          for_webpage   => False,
                                          sysrootver    => sysrootver);

      if not successful then
         raise bsheet_parsing
           with calc_dossier & "-> " & PAR.get_parse_error;
      end if;

      rec.pkgversion    := HT.SUS (thespec.calculate_pkgversion);
      rec.ignore_reason := HT.SUS (thespec.aggregated_ignore_reason);
      rec.ignored       := not HT.IsBlank (rec.ignore_reason);
      rec.scanned       := True;
      for item in Positive range 1 .. thespec.get_list_length (PSP.sp_build_deps) loop
         populate_set_depends (target, thespec.get_list_item (PSP.sp_build_deps, item), build);
      end loop;
      for item in Positive range 1 .. thespec.get_list_length (PSP.sp_buildrun_deps) loop
         populate_set_depends (target, thespec.get_list_item (PSP.sp_buildrun_deps, item),
                               buildrun);
      end loop;
      for item in Positive range 1 .. thespec.get_list_length (PSP.sp_run_deps) loop
         populate_set_depends (target, thespec.get_list_item (PSP.sp_run_deps, item), runtime);
      end loop;
      for item in Positive range 1 .. thespec.get_subpackage_length (variant) loop
         declare
            newrec     : subpackage_record;
            subpackage : String := thespec.get_subpackage_item (variant, item);
            is_primary : Boolean := False;
         begin
            newrec.subpackage   := HT.SUS (subpackage);
            newrec.never_remote := always_build;

            if subpackage /= spkg_complete and then
              subpackage /= spkg_examples and then
              subpackage /= spkg_docs and then
              HT.IsBlank (prime_pkg)
            then
               prime_pkg := newrec.subpackage;
               is_primary := True;
            end if;

            for subitem in Positive range 1 .. thespec.get_number_extra_run (subpackage) loop
               declare
                  dep : String := thespec.get_extra_runtime (subpackage, subitem);
               begin
                  populate_set_depends (target, dep, extra_runtime);
                  declare
                     --  These will pass because populate_set_depends didn't throw exception
                     portkey  : HT.Text := HT.SUS (convert_tuple_to_portkey (dep));
                     depindex : port_index := ports_keys.Element (portkey);
                     idrec    : subpackage_identifier;
                  begin
                     idrec.port := depindex;
                     idrec.subpackage := HT.SUS (extract_subpackage (dep));
                     if not newrec.spkg_run_deps.Contains (idrec) then
                        newrec.spkg_run_deps.Append (idrec);
                     end if;
                  end;
               end;
            end loop;

            if is_primary then
               for si in Positive range 1 .. thespec.get_list_length (PSP.sp_buildrun_deps) loop
                  declare
                     dep      : String := thespec.get_list_item (PSP.sp_buildrun_deps, si);
                     portkey  : HT.Text := HT.SUS (convert_tuple_to_portkey (dep));
                     depindex : port_index := ports_keys.Element (portkey);
                     idrec    : subpackage_identifier;
                  begin
                     idrec.port := depindex;
                     idrec.subpackage := HT.SUS (extract_subpackage (dep));
                     if not newrec.spkg_run_deps.Contains (idrec) then
                        newrec.spkg_run_deps.Append (idrec);
                     end if;
                  end;
               end loop;
               for si in Positive range 1 .. thespec.get_list_length (PSP.sp_run_deps) loop
                  declare
                     dep      : String := thespec.get_list_item (PSP.sp_run_deps, si);
                     portkey  : HT.Text := HT.SUS (convert_tuple_to_portkey (dep));
                     depindex : port_index := ports_keys.Element (portkey);
                     idrec    : subpackage_identifier;
                  begin
                     idrec.port := depindex;
                     idrec.subpackage := HT.SUS (extract_subpackage (dep));
                     if not newrec.spkg_run_deps.Contains (idrec) then
                        newrec.spkg_run_deps.Append (idrec);
                     end if;
                  end;
               end loop;
            end if;

            if subpackage = spkg_complete then
               for si in Positive range 1 .. thespec.get_subpackage_length (variant) loop
                  declare
                     innersub : constant String := thespec.get_subpackage_item (variant, si);
                     idrec    : subpackage_identifier;
                  begin
                     if innersub /= spkg_complete then
                        idrec.port := target;
                        idrec.subpackage := HT.SUS (innersub);
                        if not newrec.spkg_run_deps.Contains (idrec) then
                           newrec.spkg_run_deps.Append (idrec);
                        end if;
                     end if;
                  end;
               end loop;
            end if;

            rec.subpackages.Append (newrec);
         end;
      end loop;
      if variant = variant_standard then
         for item in Positive range 1 .. thespec.get_list_length (PSP.sp_opts_standard) loop
            declare
               optname : String := thespec.get_list_item (PSP.sp_opts_standard, item);
            begin
               if optname /= options_none then
                  populate_option (target, optname, thespec.option_current_setting (optname));
               end if;
            end;
         end loop;
      else
         for item in Positive range 1 .. thespec.get_list_length (PSP.sp_opts_avail) loop
            declare
               optname : String := thespec.get_list_item (PSP.sp_opts_avail, item);
            begin
               populate_option (target, optname, thespec.option_current_setting (optname));
            end;
         end loop;
      end if;
   end populate_port_data;


   --------------------------------------------------------------------------------------------
   --  populate_option
   --------------------------------------------------------------------------------------------
   procedure populate_option (target : port_index; option_name : String; setting : Boolean)
   is
      optname_text : HT.Text := HT.SUS (option_name);
   begin
      if not all_ports (target).options.Contains (optname_text) then
         all_ports (target).options.Insert (Key => optname_text, New_Item => setting);
      end if;
   end populate_option;


   --------------------------------------------------------------------------------------------
   --  populate_set_depends
   --------------------------------------------------------------------------------------------
   procedure populate_set_depends (target : port_index;
                                   tuple  : String;
                                   dtype  : dependency_type)
   is
      portkey  : HT.Text := HT.SUS (convert_tuple_to_portkey (tuple));
      depindex : port_index;
   begin
      if not ports_keys.Contains (portkey) then
         raise populate_error with "dependency on non-existent port " & tuple;
      end if;
      depindex := ports_keys.Element (portkey);
      if target = depindex then
         if dtype = extra_runtime then
            return;
         else
            raise populate_error with tuple & " can't depend on itself";
         end if;
      end if;
      if HT.USS (all_ports (depindex).port_namebase) = default_compiler then
         if dtype = extra_runtime then
            return;
         else
            raise populate_error with tuple & " belongs to the default compiler which is a " &
              "special case that can only be specified via EXRUN";
         end if;
      end if;
      if not all_ports (target).blocked_by.Contains (depindex) then
         all_ports (target).blocked_by.Insert (depindex, depindex);
      end if;
      if dtype in LR_set and then
        not all_ports (target).run_deps.Contains (depindex)
      then
         all_ports (target).run_deps.Insert (Key => depindex, New_Item => depindex);
      end if;

   end populate_set_depends;


   --------------------------------------------------------------------------------------------
   --  convert_tuple_to_portkey
   --------------------------------------------------------------------------------------------
   function convert_tuple_to_portkey (tuple : String) return String
   is
      --  tuple   format is <namebase>:<subpackage>:<variant>
      --  portkey format is <namebase>-<variant>
   begin
      if HT.count_char (tuple, LAT.Colon) /= 2 then
         raise populate_error with "tuple has invalid format: " & tuple;
      end if;
      declare
         namebase : String := HT.specific_field (tuple, 1, ":");
         variant  : String := HT.specific_field (tuple, 3, ":");
      begin
         return namebase & LAT.Colon & variant;
      end;
   end convert_tuple_to_portkey;


   --------------------------------------------------------------------------------------------
   --  extract_subpackage
   --------------------------------------------------------------------------------------------
   function extract_subpackage (tuple : String) return String
   is
      --  tuple format is <namebase>:<subpackage>:<variant>
   begin
      if HT.count_char (tuple, LAT.Colon) /= 2 then
         raise populate_error with "tuple has invalid format: " & tuple;
      end if;
      return  HT.tail (HT.head (tuple, ":"), ":");
   end extract_subpackage;


   --------------------------------------------------------------------------------------------
   --  scan_single_port
   --------------------------------------------------------------------------------------------
   function scan_single_port
     (namebase     : String;
      variant      : String;
      always_build : Boolean;
      sysrootver   : sysroot_characteristics;
      fatal        : out Boolean) return Boolean
   is
      procedure dig (cursor : block_crate.Cursor);

      conspiracy : constant String := HT.USS (PM.configuration.dir_conspiracy);
      unkindness : constant String := HT.USS (PM.configuration.dir_unkindness);

      two_partid : constant String := namebase & LAT.Colon & variant;
      portkey    : HT.Text := HT.SUS (two_partid);
      target     : port_index;
      aborted    : Boolean := False;
      indy500    : Boolean := False;

      procedure dig (cursor : block_crate.Cursor)
      is
         new_target : port_index := block_crate.Element (cursor);
      begin
         if not aborted then
            if all_ports (new_target).scan_locked then
               --  We've already seen this (circular dependency)
               raise circular_logic;
            end if;
            if not all_ports (new_target).scanned then
               populate_port_data (conspiracy   => conspiracy,
                                   unkindness   => unkindness,
                                   target       => new_target,
                                   always_build => False,
                                   sysrootver   => sysrootver);
               all_ports (new_target).scan_locked := True;
               all_ports (new_target).blocked_by.Iterate (dig'Access);
               all_ports (new_target).scan_locked := False;
               if indy500 then
                  TIO.Put_Line ("... backtrace " & get_port_variant (all_ports (new_target)));
               end if;
            end if;
         end if;
      exception
         when issue : circular_logic =>
            aborted := True;
            indy500 := True;
            TIO.Put_Line (LAT.LF & two_partid & " scan aborted because a circular dependency on " &
                            get_port_variant (all_ports (new_target)) & " was detected.");
         when issue : populate_error =>
            aborted := True;
            TIO.Put_Line ("Scan aborted during port data population.");
            TIO.Put_Line (EX.Exception_Message (issue));
         when issue : others =>
            aborted := True;
            TIO.Put_Line ("Scan aborted for an unknown reason.");
            TIO.Put_Line (EX.Exception_Message (issue));
      end dig;
   begin
      fatal := False;
      if not prescanned then
         prescan_ports_tree (conspiracy, unkindness, sysrootver);
      end if;
      if ports_keys.Contains (portkey) then
         target := ports_keys.Element (portkey);
      else
         TIO.Put_Line (namebase & " specification not listed in Mk/Misc/conspiracy-variants, ");
         TIO.Put_Line ("nor found in the custom ports directory");
         return False;
      end if;
      begin
         if all_ports (target).scanned then
            --  This can happen when a dpendency is also on the build list.
            return True;
         else
            populate_port_data (conspiracy   => conspiracy,
                                unkindness   => unkindness,
                                target       => target,
                                always_build => always_build,
                                sysrootver   => sysrootver);
         end if;
      exception
         when issue : others =>
            TIO.Put_Line ("Encountered issue with " & two_partid & " or its dependencies" &
                            LAT.LF & "  => " & EX.Exception_Message (issue));
            return False;
      end;
      all_ports (target).scan_locked := True;
      all_ports (target).blocked_by.Iterate (dig'Access);
      all_ports (target).scan_locked := False;
      if indy500 then
         TIO.Put_Line ("... backtrace " & two_partid);
         fatal := True;
      end if;
      return not aborted;
   end scan_single_port;


   --------------------------------------------------------------------------------------------
   --  set_build_priority
   --------------------------------------------------------------------------------------------
   procedure set_build_priority is
   begin
      iterate_reverse_deps;
      iterate_drill_down;
   end set_build_priority;


   --------------------------------------------------------------------------------------------
   --  iterate_reverse_deps
   --------------------------------------------------------------------------------------------
   procedure iterate_reverse_deps
   is
      procedure set_reverse (cursor : block_crate.Cursor);

      victim : port_index;

      procedure set_reverse (cursor : block_crate.Cursor)
      is
         blocker : port_index renames block_crate.Element (cursor);
      begin
         --  Using conditional insert here causes a finalization error when
         --  the program exists.  Reluctantly, do the condition check manually
         if not all_ports (blocker).blocks.Contains (victim) then
            all_ports (blocker).blocks.Insert (victim, victim);
         end if;
      end set_reverse;

   begin
      for port in port_index'First .. last_port loop
         if all_ports (port).scanned then
            victim := port;
            all_ports (port).blocked_by.Iterate (set_reverse'Access);
         end if;
      end loop;
   end iterate_reverse_deps;


   --------------------------------------------------------------------------------------------
   --  iterate_reverse_deps
   --------------------------------------------------------------------------------------------
   procedure iterate_drill_down
   is
      monaco : Boolean := False;
   begin
      rank_queue.Clear;
      for port in port_index'First .. last_port loop
         if all_ports (port).scanned then
            drill_down (next_target => port, circular_flag => monaco);
            declare
               ndx : constant port_index   := port_index (all_ports (port).reverse_score);
               QR  : constant queue_record := (ap_index      => port,
                                               reverse_score => ndx);
            begin
               rank_queue.Insert (New_Item => QR);
            end;
         end if;
         if monaco then
            raise circular_logic with "Circular dependency detected during drill down";
         end if;
      end loop;
   end iterate_drill_down;


   --------------------------------------------------------------------------------------------
   --  drill_down
   --------------------------------------------------------------------------------------------
   procedure drill_down (next_target : port_index; circular_flag : in out Boolean)
   is
      procedure stamp_and_drill (cursor : block_crate.Cursor);
      procedure slurp_scanned (cursor : block_crate.Cursor);

      rec : port_record renames all_ports (next_target);

      procedure slurp_scanned (cursor : block_crate.Cursor)
      is
         rev_id  : port_index := block_crate.Element (Position => cursor);
      begin
         if not all_ports (next_target).all_reverse.Contains (rev_id) then
            all_ports (next_target).all_reverse.Insert (rev_id, rev_id);
         end if;
      end slurp_scanned;

      procedure stamp_and_drill (cursor : block_crate.Cursor)
      is
         pmc : port_index := block_crate.Element (Position => cursor);
      begin
         if all_ports (pmc).scan_locked then
            --  We've already seen this port (circular dependency)
            circular_flag := True;
            TIO.Put_Line ("!! Dependency violation on " & get_port_variant (all_ports (pmc)));
         else
            if not all_ports (next_target).all_reverse.Contains (pmc) then
               all_ports (next_target).all_reverse.Insert (pmc, pmc);
            end if;

            if not all_ports (pmc).rev_scanned then
               drill_down (next_target => pmc, circular_flag => circular_flag);
            end if;
            all_ports (pmc).all_reverse.Iterate (slurp_scanned'Access);
         end if;
      end stamp_and_drill;

   begin
      if not rec.scanned then
         return;
      end if;
      if rec.rev_scanned or else circular_flag then
         --  It is possible to get here if an earlier port scanned this port
         --  as a reverse dependencies
         return;
      end if;
      rec.scan_locked := True;
      rec.blocks.Iterate (stamp_and_drill'Access);
      rec.scan_locked := False;

      rec.reverse_score := port_index (rec.all_reverse.Length);
      rec.rev_scanned := True;

      if circular_flag then
         TIO.Put_Line ("... backtrace " & get_port_variant (all_ports (next_target)));
      end if;
   end drill_down;


   --------------------------------------------------------------------------------------------
   --  scan_provided_list_of_ports
   --------------------------------------------------------------------------------------------
   function scan_provided_list_of_ports
     (always_build : Boolean;
      sysrootver   : sysroot_characteristics) return Boolean
   is
      procedure scan (plcursor : string_crate.Cursor);

      successful    : Boolean := True;
      just_stop_now : Boolean;
      compiler_key  : HT.Text := HT.SUS (default_compiler & ":" & variant_standard);

      procedure scan (plcursor : string_crate.Cursor)
      is
         origin   : constant String := HT.USS (string_crate.Element (plcursor));
         namebase : constant String := HT.part_1 (origin, ":");
         variant  : constant String := HT.part_2 (origin, ":");
      begin
         if not successful then
            return;
         end if;
         if Signals.graceful_shutdown_requested then
            successful := False;
            return;
         end if;
         if not scan_single_port (namebase     => namebase,
                                  variant      => variant,
                                  always_build => always_build,
                                  sysrootver   => sysrootver,
                                  fatal        => just_stop_now)
         then
            if just_stop_now then
               --  backtrace outputs, no need for more information.
               null;
            else
               TIO.Put_Line ("Scan of " & origin & " failed, bulk run cancelled");
            end if;
            successful := False;
         end if;
      end scan;
   begin
      portlist.Iterate (Process => scan'Access);
      if successful and then
        not portlist.Contains (compiler_key)
      then
         --  We always need current information on the default compiler
         begin
            skeleton_compiler_data (conspiracy => HT.USS (PM.configuration.dir_conspiracy),
                                    unkindness => HT.USS (PM.configuration.dir_unkindness),
                                    target     => ports_keys.Element (compiler_key),
                                    sysrootver => sysrootver);
         exception
            when others =>
               TIO.Put_Line ("Scan of the compiler port failed, fatal issue");
               successful := False;
         end;
      end if;
      return successful;
   end scan_provided_list_of_ports;


   --------------------------------------------------------------------------------------------
   --  generate_conspiracy_index
   --------------------------------------------------------------------------------------------
   function tohex (value : AF) return Character is
   begin
      case value is
         when 0 .. 9 => return Character'Val (Character'Pos ('0') + value);
         when others => return Character'Val (Character'Pos ('A') + value - 10);
      end case;
   end tohex;


   --------------------------------------------------------------------------------------------
   --  generate_conspiracy_index
   --------------------------------------------------------------------------------------------
   procedure generate_conspiracy_index (sysrootver : sysroot_characteristics)
   is
      procedure scan_port (position : string_crate.Cursor);

      conspiracy : constant String := HT.USS (PM.configuration.dir_conspiracy);
      misc_dir   : constant String := conspiracy & "/Mk/Misc/";
      finalcvar  : constant String := misc_dir & "conspiracy_variants";
      finalfpceq : constant String := misc_dir & "fpc_equivalents";
      summary    : constant String := misc_dir & "summary.txt";
      repology   : constant String := misc_dir & "repology.json";
      indexfile  : TIO.File_Type;
      fpcfile    : TIO.File_Type;
      repofile   : TIO.File_Type;
      bucket     : bucket_code;
      total_ports    : Natural := 0;
      total_variants : Natural := 0;
      total_subpkgs  : Natural := 0;

      procedure scan_port (position : string_crate.Cursor)
      is
         namebase   : String := HT.USS (string_crate.Element (position));
         successful : Boolean;
         customspec : PSP.Portspecs;
         arch_focus : supported_arch := x86_64;  -- unused, pick one
         dossier    : constant String := conspiracy & "/bucket_" & bucket & "/" & namebase;
      begin
         PAR.parse_specification_file (dossier         => dossier,
                                       specification   => customspec,
                                       opsys_focus     => platform_type,
                                       arch_focus      => arch_focus,
                                       success         => successful,
                                       stop_at_targets => True);
         if not successful then
            raise bsheet_parsing with dossier & "-> " & PAR.get_parse_error;
         end if;

         declare
            varcnt  : Natural := customspec.get_number_of_variants;
            varlist : String  := customspec.get_field_value (PSP.sp_variants);
         begin
            total_ports := total_ports + 1;
            total_variants := total_variants + varcnt;
            TIO.Put (indexfile, bucket & " " & namebase & " " & HT.int2str (varcnt));
            for varx in Integer range 1 .. varcnt loop
               declare
                  variant : String  := HT.specific_field (varlist, varx, ", ");
                  spkgcnt : Natural := customspec.get_subpackage_length (variant);
               begin
                  total_subpkgs := total_subpkgs  + spkgcnt;
                  TIO.Put (indexfile, " " & variant);
               end;
            end loop;
            TIO.Put_Line (indexfile, "");
            declare
               vers : constant String := customspec.get_field_value (PSP.sp_version);
            begin
               TIO.Put (fpcfile, namebase & " " & vers & " ");
               if customspec.port_is_generated then
                  TIO.Put_Line (fpcfile, "generated");
               else
                  TIO.Put_Line (fpcfile, customspec.equivalent_fpc_port);
               end if;
            end;
            Port_Specification.Json.describe_port
              (specs   => customspec,
               dossier => repofile,
               bucket  => bucket,
               index   => total_ports);
         end;
      end scan_port;
   begin
      LOG.set_scan_start_time (CAL.Clock);

      TIO.Create (File => indexfile,
                  Mode => TIO.Out_File,
                  Name => finalcvar);

      TIO.Create (File => fpcfile,
                  Mode => TIO.Out_File,
                  Name => finalfpceq);

      TIO.Create (File => repofile,
                  Mode => TIO.Out_File,
                  Name => repology);

      TIO.Put
        (repofile,
           UTL.json_object (True, 0, 1) &
           UTL.json_name_complex ("ravenports", 1, 1) &
           UTL.json_array (True, 2));

      for highdigit in AF'Range loop
         for lowdigit in AF'Range loop
            bucket := tohex (highdigit) & tohex (lowdigit);
            declare
               bucket_dir   : constant String := conspiracy & "/bucket_" & bucket;
               Inner_Search : DIR.Search_Type;
               Inner_Dirent : DIR.Directory_Entry_Type;
               tempstore    : string_crate.Vector;
               use type DIR.File_Kind;
            begin
               if DIR.Exists (bucket_dir) and then
                 DIR.Kind (bucket_dir) = DIR.Directory
               then

                  DIR.Start_Search (Search    => Inner_Search,
                                    Directory => bucket_dir,
                                    Filter    => (DIR.Ordinary_File => True, others => False),
                                    Pattern   => "*");

                  while DIR.More_Entries (Inner_Search) loop
                     DIR.Get_Next_Entry (Search => Inner_Search, Directory_Entry => Inner_Dirent);
                     tempstore.Append (HT.SUS (DIR.Simple_Name (Inner_Dirent)));
                  end loop;
                  DIR.End_Search (Inner_Search);
                  sorter.Sort (tempstore);
                  tempstore.Iterate (scan_port'Access);
               end if;
            end;
         end loop;
      end loop;

      TIO.Close (indexfile);
      TIO.Close (fpcfile);
      LOG.set_scan_complete (CAL.Clock);

      TIO.Put_Line ("Index successfully generated.");
      TIO.Put_Line ("       Total ports : " & HT.int2str (total_ports));
      TIO.Put_Line ("    Total variants : " & HT.int2str (total_variants));
      TIO.Put_Line ("    Total packages : " & HT.int2str (total_subpkgs));
      TIO.Put_Line ("  Linear scan time : " & LOG.scan_duration);

      TIO.Put_Line
        (repofile,
           UTL.json_array (False, 2) &
           UTL.json_name_complex ("summary", 2, 1) &
           UTL.json_object (True, 2, 1) &
           UTL.json_nvpair_integer ("ports", total_ports, 1, 3) &
           UTL.json_nvpair_integer ("variants", total_variants, 2, 3) &
           UTL.json_nvpair_integer ("packages", total_subpkgs, 3, 3) &
           UTL.json_object (False, 2, 1) &
           LAT.Right_Curly_Bracket);

      TIO.Create (File => indexfile,
                  Mode => TIO.Out_File,
                  Name => summary);

      TIO.Put_Line (indexfile, "  Statistics derived from generation of conspiracy index");
      TIO.Put_Line (indexfile, "==========================================================");
      TIO.Put_Line (indexfile, "       Total ports : " & HT.int2str (total_ports));
      TIO.Put_Line (indexfile, "    Total variants : " & HT.int2str (total_variants));
      TIO.Put_Line (indexfile, "    Total packages : " & HT.int2str (total_subpkgs));
      TIO.Put_Line (indexfile, "  Linear scan time : " & LOG.scan_duration);

      TIO.Close (indexfile);

   exception
      when issue : others =>
         if TIO.Is_Open (indexfile) then
            TIO.Close (indexfile);
         end if;
         if TIO.Is_Open (fpcfile) then
            TIO.Close (fpcfile);
         end if;
         if TIO.Is_Open (repofile) then
            TIO.Close (repofile);
         end if;
         TIO.Put_Line ("Failure encountered: " & EX.Exception_Message (issue));
   end generate_conspiracy_index;


   --------------------------------------------------------------------------------------------
   --  version_difference
   --------------------------------------------------------------------------------------------
   function version_difference (id : port_id; kind : out verdiff) return String
   is
      procedure each_subpackage (position : subpackage_crate.Cursor);

      pkg8    : constant String := HT.USS (PM.configuration.sysroot_pkg8);
      dir_pkg : constant String := HT.USS (PM.configuration.dir_repository);
      version : constant String := HT.USS (all_ports (id).pkgversion);
      origin  : constant String := get_port_variant (id);
      upgrade : HT.Text;
      all_present : Boolean := True;

      procedure each_subpackage (position : subpackage_crate.Cursor)
      is
         rec : subpackage_record renames subpackage_crate.Element (position);
         subpackage   : String := HT.USS (rec.subpackage);
         current      : String := calculate_package_name (id, subpackage);
         base_pattern : String := HT.USS (all_ports (id).port_namebase) & "-" &
                                  HT.USS (all_ports (id).port_variant) & "-";
         pattern      : String := base_pattern & "*" & arc_ext;
         pkg_search   : DIR.Search_Type;
         dirent       : DIR.Directory_Entry_Type;
      begin

         if rec.pkg_present then
            return;
         else
            all_present := False;
         end if;
         if not HT.IsBlank (upgrade) then
            return;
         end if;

         DIR.Start_Search (Search    => pkg_search,
                           Directory => dir_pkg,
                           Filter    => (DIR.Ordinary_File => True, others => False),
                           Pattern   => pattern);
         while DIR.More_Entries (Search => pkg_search) loop
            DIR.Get_Next_Entry (Search => pkg_search, Directory_Entry => dirent);
            declare
               sname      : String := DIR.Simple_Name (dirent);
               verend     : Natural := sname'Length - arc_ext'Length;
               command    : String := pkg8 & " query -F "  & dir_pkg & "/" & sname & " %o";
               status     : Integer;
               testorigin : HT.Text := Unix.piped_command (command, status);
            begin
               if status = 0 and then HT.equivalent (testorigin, origin) then
                  upgrade := HT.SUS (" (" & sname (base_pattern'Length + 1 .. verend) &
                                       " => " & version & ")");
               end if;
            end;
         end loop;
         DIR.End_Search (pkg_search);
      end each_subpackage;


   begin
      all_ports (id).subpackages.Iterate (each_subpackage'Access);
      if all_present then
         kind := rebuild;
         return " (rebuild " & version & ")";
      end if;
      if not HT.IsBlank (upgrade) then
         kind := change;
         return HT.USS (upgrade);
      end if;
      kind := newbuild;
      return " (new " & version & ")";
   end version_difference;


   --------------------------------------------------------------------------------------------
   --  display_results_of_dry_run
   --------------------------------------------------------------------------------------------
   procedure display_results_of_dry_run
   is
      procedure print (cursor : ranking_crate.Cursor);
      listlog  : TIO.File_Type;
      filename : constant String   := "/tmp/ravenadm_status_results.txt";
      max_lots : constant scanners := get_max_lots;
      elapsed  : constant String   := LOG.scan_duration;
      goodlog  : Boolean;

      procedure print (cursor : ranking_crate.Cursor)
      is
         id     : port_id := ranking_crate.Element (cursor).ap_index;
         kind   : verdiff;
         diff   : constant String := version_difference (id, kind);
         origin : constant String := get_port_variant (id);
      begin
         case kind is
            when newbuild => TIO.Put_Line ("  N => " & origin);
            when rebuild  => TIO.Put_Line ("  R => " & origin);
            when change   => TIO.Put_Line ("  U => " & origin & diff);
         end case;
         if goodlog then
            TIO.Put_Line (listlog, origin & diff);
         end if;
      end print;
   begin
      begin
         TIO.Create (File => listlog, Mode => TIO.Out_File, Name => filename);
         goodlog := True;
      exception
         when others => goodlog := False;
      end;
      TIO.Put_Line ("These are the ports that would be built ([N]ew, " &
                   "[R]ebuild, [U]pgrade):");
      rank_queue.Iterate (print'Access);
      TIO.Put_Line ("Total packages that would be built:" &
                      rank_queue.Length'Img);
      if goodlog then
         TIO.Put_Line
           (listlog,
            LAT.LF &
              LAT.LF & "------------------------------" &
              LAT.LF & "--  Statistics" &
              LAT.LF & "------------------------------" &
              LAT.LF & " Ports scanned :" & last_port'Img &
              LAT.LF & "  Elapsed time : " & elapsed &
              LAT.LF & "   Parallelism :" & max_lots'Img & " scanners" &
              "          ncpu :" & Parameters.configuration.number_cores'Img);
         TIO.Close (listlog);
         TIO.Put_Line ("The complete build list can also be found at:"
                       & LAT.LF & filename);
      end if;
   end display_results_of_dry_run;


   --------------------------------------------------------------------------------------------
   --  gather_distfile_set
   --------------------------------------------------------------------------------------------
   function gather_distfile_set (sysrootver : sysroot_characteristics) return Boolean
   is
      good_scan    : Boolean;
      using_screen : constant Boolean := Unix.screen_attached;
      conspiracy   : constant String := HT.USS (PM.configuration.dir_conspiracy);
      unkindness   : constant String := HT.USS (PM.configuration.dir_unkindness);
   begin
      prescan_conspiracy_index_for_distfiles (conspiracy, unkindness, sysrootver);
      LOG.set_scan_start_time (CAL.Clock);
      parallel_distfile_scan (conspiracy    => conspiracy,
                              sysrootver    => sysrootver,
                              success       => good_scan,
                              show_progress => using_screen);
      LOG.set_scan_complete (CAL.Clock);
      return good_scan;
   end gather_distfile_set;


   --------------------------------------------------------------------------------------------
   --  prescan_conspiracy_index_for_distfiles
   --------------------------------------------------------------------------------------------
   procedure prescan_conspiracy_index_for_distfiles
     (conspiracy : String;
      unkindness : String;
      sysrootver : sysroot_characteristics)
   is
      conspindex_path : constant String := conspiracy & conspindex;
      max_lots        : constant scanners := get_max_lots;
      custom_avail    : constant Boolean := unkindness /= PM.no_unkindness;
   begin
      if not DIR.Exists (conspindex_path) then
         raise missing_index with conspindex;
      end if;

      declare
         fulldata  : String := FOP.get_file_contents (conspindex_path);
         markers   : HT.Line_Markers;
         linenum   : Natural := 0;
      begin
         HT.initialize_markers (fulldata, markers);
         loop
            exit when not HT.next_line_present (fulldata, markers);
            linenum := linenum + 1;
            declare
               line     : constant String := HT.extract_line (fulldata, markers);
               bucket   : constant String := HT.specific_field (line, 1);
               namebase : constant String := HT.specific_field (line, 2);
               bsheet   : constant String := "/bucket_" & bucket & "/" & namebase;
               linestr  : constant String := ", line " & HT.int2str (linenum);
            begin
               if bucket'Length /= 2 or else namebase'Length = 0 then
                  raise bad_index_data with conspindex & linestr;
               end if;
               if not DIR.Exists (conspiracy & bsheet) then
                  raise bad_index_data
                    with conspindex & bsheet & " buildsheet does not exist" & linestr;
               end if;
               if custom_avail and then DIR.Exists (unkindness & bsheet) then
                  --  postpone custom port scan (done prescan_unkindness)
                  null;
               else
                  declare
                     portkey  : HT.Text := HT.SUS (namebase);
                     kc       : portkey_crate.Cursor;
                     success  : Boolean;
                  begin
                     ports_keys.Insert (Key      => portkey,
                                        New_Item => lot_counter,
                                        Position => kc,
                                        Inserted => success);
                     last_port := lot_counter;
                     all_ports (lot_counter).sequence_id   := lot_counter;
                     all_ports (lot_counter).key_cursor    := kc;
                     all_ports (lot_counter).port_namebase := HT.SUS (namebase);
                     all_ports (lot_counter).bucket        := bucket_code (bucket);
                     all_ports (lot_counter).unkind_custom := False;
                     make_queue (lot_number).Append (lot_counter);
                     lot_counter := lot_counter + 1;
                     if lot_number = max_lots then
                        lot_number := 1;
                     else
                        lot_number := lot_number + 1;
                     end if;
                  end;
               end if;
            end;
         end loop;
      end;
   end prescan_conspiracy_index_for_distfiles;


   --------------------------------------------------------------------------------------------
   --  linear_scan_unkindness_for_distfiles
   --------------------------------------------------------------------------------------------
   procedure linear_scan_unkindness_for_distfiles (unkindness : String)
   is
      procedure insert_distfile (dist_subdir : String; distfile_group : String);

      dindex : port_index := 0;

      procedure insert_distfile (dist_subdir : String; distfile_group : String)
      is
         function determine_distname return String;
         use_subdir : Boolean := (dist_subdir /= "");

         function determine_distname return String
         is
            distfile : String := HT.part_1 (distfile_group, ":");
         begin
            if use_subdir then
               return dist_subdir & "/" & distfile;
            else
               return distfile;
            end if;
         end determine_distname;

         distfile_path : HT.Text := HT.SUS (determine_distname);
      begin
         if not distfile_set.Contains (distfile_path) then
            dindex := dindex + 1;
            distfile_set.Insert (distfile_path, dindex);
         end if;
      end insert_distfile;
   begin
      if unkindness = PM.no_unkindness or else
        not DIR.Exists (unkindness)
      then
         return;
      end if;

      for highdigit in AF'Range loop
         for lowdigit in AF'Range loop
            declare
               bucket       : bucket_code := tohex (highdigit) & tohex (lowdigit);
               bucket_dir   : constant String := unkindness & "/bucket_" & bucket;
               Inner_Search : DIR.Search_Type;
               Inner_Dirent : DIR.Directory_Entry_Type;
               use type DIR.File_Kind;
            begin
               if DIR.Exists (bucket_dir) and then
                 DIR.Kind (bucket_dir) = DIR.Directory
               then

                  DIR.Start_Search (Search    => Inner_Search,
                                    Directory => bucket_dir,
                                    Filter    => (DIR.Ordinary_File => True, others => False),
                                    Pattern   => "*");

                  while DIR.More_Entries (Inner_Search) loop
                     DIR.Get_Next_Entry (Inner_Search, Inner_Dirent);
                     declare
                        namebase : String := DIR.Simple_Name (Inner_Dirent);
                        successful : Boolean;
                        customspec : PSP.Portspecs;
                        arch_focus : supported_arch := x86_64;  -- unused, pick one
                        buildsheet : constant String := "/bucket_" & bucket & "/" & namebase;
                     begin
                        PAR.parse_specification_file (dossier         => unkindness & buildsheet,
                                                      specification   => customspec,
                                                      opsys_focus     => platform_type,
                                                      arch_focus      => arch_focus,
                                                      success         => successful,
                                                      stop_at_targets => True);
                        if not successful then
                           raise bsheet_parsing
                             with unkindness & buildsheet & "-> " & PAR.get_parse_error;
                        end if;
                        declare
                           dist_subdir : String := customspec.get_field_value (PSP.sp_distsubdir);
                           num_dfiles  : Natural := customspec.get_list_length (PSP.sp_distfiles);
                        begin
                           for df in 1 .. num_dfiles loop
                              insert_distfile (dist_subdir,
                                               customspec.get_list_item (PSP.sp_distfiles, df));
                           end loop;
                        end;
                     end;
                  end loop;
                  DIR.End_Search (Inner_Search);
               end if;
            end;
         end loop;
      end loop;
   end linear_scan_unkindness_for_distfiles;


   --------------------------------------------------------------------------------------------
   --  parallel_distfile_scan
   --------------------------------------------------------------------------------------------
   procedure parallel_distfile_scan
     (conspiracy    : String;
      sysrootver    : sysroot_characteristics;
      success       : out Boolean;
      show_progress : Boolean)
   is
      procedure combine (position : portkey_crate.Cursor);

      finished      : array (scanners) of Boolean := (others => False);
      task_storage  : array (scanners) of portkey_crate.Map;
      combined_wait : Boolean := True;
      aborted       : Boolean := False;
      dindex        : port_index := port_index (distfile_set.Length);

      procedure combine (position : portkey_crate.Cursor)
      is
         distfile : HT.Text := portkey_crate.Key (position);
      begin
         if not distfile_set.Contains (distfile) then
            dindex := dindex + 1;
            distfile_set.Insert (distfile, dindex);
         end if;
      end combine;

      task type scan (lot : scanners);
      task body scan
      is
         procedure populate (cursor : subqueue.Cursor);
         procedure populate (cursor : subqueue.Cursor)
         is
            procedure insert_distfile (dist_subdir : String; distfile : String);

            target_port : port_index := subqueue.Element (cursor);
            namebase    : String := HT.USS (all_ports (target_port).port_namebase);
            bucket      : bucket_code := all_ports (target_port).bucket;
            customspec  : PSP.Portspecs;
            successful  : Boolean;
            arch_focus  : supported_arch := x86_64;  -- unused, pick one
            buildsheet  : constant String := "/bucket_" & bucket & "/" & namebase;

            procedure insert_distfile (dist_subdir : String; distfile : String)
            is
               function determine_distname return String;
               use_subdir : Boolean := (dist_subdir /= "");

               function determine_distname return String is
               begin
                  if use_subdir then
                     return dist_subdir & "/" & distfile;
                  else
                     return distfile;
                  end if;
               end determine_distname;

               distfile_path : HT.Text := HT.SUS (determine_distname);
            begin
               if not task_storage (lot).Contains (distfile_path) then
                  task_storage (lot).Insert (distfile_path, 1);
               end if;
            end insert_distfile;
         begin
            if not aborted then
               PAR.parse_specification_file (dossier         => conspiracy & buildsheet,
                                             specification   => customspec,
                                             opsys_focus     => platform_type,
                                             arch_focus      => arch_focus,
                                             success         => successful,
                                             stop_at_targets => True);
               if not successful then
                  TIO.Put_Line (LAT.LF & "culprit: " & buildsheet & "-> " & PAR.get_parse_error);
                  aborted := True;
               end if;
               declare
                  dist_subdir : String := customspec.get_field_value (PSP.sp_distsubdir);
                  num_dfiles  : Natural := customspec.get_list_length (PSP.sp_distfiles);
               begin
                  for df in 1 .. num_dfiles loop
                     insert_distfile (dist_subdir,
                                      customspec.get_list_item (PSP.sp_distfiles, df));
                  end loop;
               end;
               mq_progress (lot) := mq_progress (lot) + 1;
            end if;
         end populate;
      begin
         make_queue (lot).Iterate (populate'Access);
         finished (lot) := True;
      end scan;

      scan_01 : scan (lot => 1);
      scan_02 : scan (lot => 2);
      scan_03 : scan (lot => 3);
      scan_04 : scan (lot => 4);
      scan_05 : scan (lot => 5);
      scan_06 : scan (lot => 6);
      scan_07 : scan (lot => 7);
      scan_08 : scan (lot => 8);
      scan_09 : scan (lot => 9);
      scan_10 : scan (lot => 10);
      scan_11 : scan (lot => 11);
      scan_12 : scan (lot => 12);
      scan_13 : scan (lot => 13);
      scan_14 : scan (lot => 14);
      scan_15 : scan (lot => 15);
      scan_16 : scan (lot => 16);
      scan_17 : scan (lot => 17);
      scan_18 : scan (lot => 18);
      scan_19 : scan (lot => 19);
      scan_20 : scan (lot => 20);
      scan_21 : scan (lot => 21);
      scan_22 : scan (lot => 22);
      scan_23 : scan (lot => 23);
      scan_24 : scan (lot => 24);
      scan_25 : scan (lot => 25);
      scan_26 : scan (lot => 26);
      scan_27 : scan (lot => 27);
      scan_28 : scan (lot => 28);
      scan_29 : scan (lot => 29);
      scan_30 : scan (lot => 30);
      scan_31 : scan (lot => 31);
      scan_32 : scan (lot => 32);

   begin
      TIO.Put_Line ("Scanning entire ports tree for distfiles.");
      while combined_wait loop
         delay 1.0;
         if show_progress then
            TIO.Put (scan_progress);
         end if;
         combined_wait := False;
         for j in scanners'Range loop
            if not finished (j) then
               combined_wait := True;
               exit;
            end if;
         end loop;
         if Signals.graceful_shutdown_requested then
            aborted := True;
         end if;
      end loop;

      success := not aborted;

      if success then
         --  Now that the scanners are complete, we can combine the results
         for j in scanners'Range loop
            task_storage (j).Iterate (combine'Access);
         end loop;
      end if;

   end parallel_distfile_scan;


   --------------------------------------------------------------------------------------------
   --  display_kmg
   --------------------------------------------------------------------------------------------
   function display_kmg (number : disktype) return String
   is
      type kmgtype is delta 0.01 digits 6;
      kilo : constant disktype := 1024;
      mega : constant disktype := kilo * kilo;
      giga : constant disktype := kilo * mega;
      XXX  : kmgtype;
   begin
      if number > giga then
         XXX := kmgtype (number / giga);
         return XXX'Img & " gigabytes";
      elsif number > mega then
         XXX := kmgtype (number / mega);
         return XXX'Img & " megabytes";
      else
         XXX := kmgtype (number / kilo);
         return XXX'Img & " kilobytes";
      end if;
   end display_kmg;


   --------------------------------------------------------------------------------------------
   --  purge_obsolete_distfiles
   --------------------------------------------------------------------------------------------
   procedure purge_obsolete_distfiles
   is
      procedure kill (position : portkey_crate.Cursor);
      procedure find_actual_tarballs (folder : String);

      distfiles_directory : String := Unix.true_path (HT.USS (PM.configuration.dir_distfiles));
      abort_purge  : Boolean := False;
      bytes_purged : disktype := 0;
      rmfiles      : portkey_crate.Map;

      procedure kill (position : portkey_crate.Cursor)
      is
         tarball : String := HT.USS (portkey_crate.Key (position));
         path    : String := distfiles_directory & "/" & tarball;
      begin
         TIO.Put_Line ("Deleting " & tarball);
         DIR.Delete_File (path);
      end kill;

      procedure find_actual_tarballs (folder : String)
      is
         procedure walkdir (item : DIR.Directory_Entry_Type);
         procedure print (item : DIR.Directory_Entry_Type);

         uniqid     : port_id := 0;
         leftindent : Natural := distfiles_directory'Length + 2;

         procedure print (item : DIR.Directory_Entry_Type)
         is
            FN    : constant String := DIR.Full_Name (item);
            tball : HT.Text := HT.SUS (FN (leftindent .. FN'Last));
         begin
            if not distfile_set.Contains (tball) then
               if not rmfiles.Contains (tball) then
                  uniqid := uniqid + 1;
                  rmfiles.Insert (Key => tball, New_Item => uniqid);
                  bytes_purged := bytes_purged + disktype (DIR.Size (FN));
               end if;
            end if;
         end print;

         procedure walkdir (item : DIR.Directory_Entry_Type) is
         begin
            if DIR.Simple_Name (item) /= "." and then
              DIR.Simple_Name (item) /= ".."
            then
               find_actual_tarballs (DIR.Full_Name (item));
            end if;
         exception
            when DIR.Name_Error =>
               abort_purge := True;
               TIO.Put_Line ("walkdir: " & folder & " directory does not exist");
         end walkdir;

      begin
         DIR.Search (folder, "*", (DIR.Ordinary_File => True, others => False), print'Access);
         DIR.Search (folder, "",  (DIR.Directory => True, others => False), walkdir'Access);
      exception
         when DIR.Name_Error =>
            abort_purge := True;
            TIO.Put_Line ("The " & folder & " directory does not exist");
         when DIR.Use_Error =>
            abort_purge := True;
            TIO.Put_Line ("Searching " & folder & " directory is not supported");
         when failed : others =>
            abort_purge := True;
            TIO.Put_Line ("purge_obsolete_distfiles: Unknown error - directory search");
            TIO.Put_Line (EX.Exception_Information (failed));
      end find_actual_tarballs;
   begin
      find_actual_tarballs (distfiles_directory);
      if abort_purge then
         TIO.Put_Line ("Distfile purge operation aborted.");
      else
         rmfiles.Iterate (kill'Access);
         TIO.Put_Line ("Recovered" & display_kmg (bytes_purged));
      end if;
   end purge_obsolete_distfiles;


   --------------------------------------------------------------------------------------------
   --  scan_repository
   --------------------------------------------------------------------------------------------
   function scan_repository (repository : String) return Boolean
   is
      pkg_search : DIR.Search_Type;
      dirent     : DIR.Directory_Entry_Type;
      pkg_index  : scanners := scanners'First;
      result     : Boolean := False;
   begin
      DIR.Start_Search (Search    => pkg_search,
                        Directory => repository,
                        Filter    => (DIR.Ordinary_File => True, others => False),
                        Pattern   => "*" & arc_ext);
      while DIR.More_Entries (Search => pkg_search) loop
         DIR.Get_Next_Entry (Search => pkg_search, Directory_Entry => dirent);
         declare
            pkgname : HT.Text := HT.SUS (DIR.Simple_Name (dirent));
         begin
            package_list.Append (pkgname);
            result := True;
         end;
      end loop;
      DIR.End_Search (pkg_search);
      return result;
   end scan_repository;


   --------------------------------------------------------------------------------------------
   --  store_port_dependencies
   --------------------------------------------------------------------------------------------
   procedure store_port_dependencies
     (port       : port_index;
      conspiracy : String;
      unkindness : String;
      sysrootver : sysroot_characteristics)
   is
      function calc_dossier return String;

      rec   : port_record renames all_ports (port);
      nbase : constant String := HT.USS (rec.port_namebase);

      function calc_dossier return String
      is
         buildsheet : String := "/bucket_" & rec.bucket & "/" & nbase;
      begin
         if rec.unkind_custom then
            return unkindness & buildsheet;
         else
            return conspiracy & buildsheet;
         end if;
      end calc_dossier;

      thespec    : PSP.Portspecs;
      successful : Boolean;
      dossier    : constant String := calc_dossier;
      variant    : constant String := HT.USS (rec.port_variant);
   begin
      OPS.parse_and_transform_buildsheet (specification => thespec,
                                          successful    => successful,
                                          buildsheet    => dossier,
                                          variant       => variant,
                                          portloc       => "",
                                          excl_targets  => True,
                                          avoid_dialog  => True,
                                          for_webpage   => False,
                                          sysrootver    => sysrootver);
      if not successful then
         --  fail silently.  The issue is caught in pass #2
         return;
      end if;

      all_ports (port).ignore_reason := HT.SUS (thespec.get_tagline (variant));
      all_ports (port).port_namebase := HT.SUS (nbase);
      all_ports (port).port_variant  := HT.SUS (variant);
      all_ports (port).pkgversion    := HT.SUS (thespec.calculate_pkgversion);
      all_ports (port).scanned       := True;

      for item in Positive range 1 .. thespec.get_list_length (PSP.sp_build_deps) loop
         populate_set_depends (port, thespec.get_list_item (PSP.sp_build_deps, item), build);
      end loop;
      for item in Positive range 1 .. thespec.get_list_length (PSP.sp_buildrun_deps) loop
         populate_set_depends (port, thespec.get_list_item (PSP.sp_buildrun_deps, item), buildrun);
      end loop;
      for item in Positive range 1 .. thespec.get_list_length (PSP.sp_run_deps) loop
         populate_set_depends (port, thespec.get_list_item (PSP.sp_run_deps, item), runtime);
      end loop;

      for item in Positive range 1 .. thespec.get_subpackage_length (variant) loop
         declare
            subpackage : String := thespec.get_subpackage_item (variant, item);
         begin
            for subitem in Positive range 1 .. thespec.get_number_extra_run (subpackage) loop
               declare
                  dep : String := thespec.get_extra_runtime (subpackage, subitem);
               begin
                  populate_set_depends (port, dep, extra_runtime);
               end;
            end loop;
         end;
      end loop;
   end store_port_dependencies;


   --------------------------------------------------------------------------------------------
   --  blocked_text_block
   --------------------------------------------------------------------------------------------
   function blocked_text_block (port : port_index) return String
   is
      procedure scan  (position : block_crate.Cursor);
      procedure print (position : string_crate.Cursor);

      result : HT.Text;
      tempstore : string_crate.Vector;

      procedure scan (position : block_crate.Cursor)
      is
         blocked : port_index renames block_crate.Element (position);
         pv      : constant String := get_port_variant (all_ports (blocked));
      begin
         tempstore.Append (HT.SUS (pv));
      end scan;

      procedure print (position : string_crate.Cursor)
      is
         pvkey  : HT.Text renames string_crate.Element (position);
         pndx   : constant port_index := ports_keys.Element (pvkey);
         namebase : constant String := HT.USS (all_ports (pndx).port_namebase);
         variant  : constant String := HT.USS (all_ports (pndx).port_variant);
         bucket   : constant String := "bucket_" & UTL.bucket (namebase);
      begin
         HT.SU.Append (result, get_port_variant (all_ports (pndx)) & ";" &
                         "../../../" & bucket & "/" & namebase & "/" & variant & ";" &
                         HT.USS (all_ports (pndx).ignore_reason) & LAT.LF);
      end print;
   begin
      all_ports (port).blocks.Iterate (scan'Access);
      sorter.Sort (tempstore);
      tempstore.Iterate (print'Access);
      return HT.USS (result);
   end blocked_text_block;


   --------------------------------------------------------------------------------------------
   --  generate_single_page
   --------------------------------------------------------------------------------------------
   function generate_single_page
     (port       : port_index;
      workzone   : String;
      www_site   : String;
      conspiracy : String;
      unkindness : String;
      cdatetime  : CAL.Time;
      mdatetime  : CAL.Time;
      sysrootver : sysroot_characteristics)
     return Boolean
   is
      function calc_dossier return String;

      rec   : port_record renames all_ports (port);
      nbase : constant String := HT.USS (rec.port_namebase);

      function calc_dossier return String
      is
         buildsheet : String := "/bucket_" & rec.bucket & "/" & nbase;
      begin
         if rec.unkind_custom then
            return unkindness & buildsheet;
         else
            return conspiracy & buildsheet;
         end if;
      end calc_dossier;

      thespec    : PSP.Portspecs;
      successful : Boolean;
      html_page  : TIO.File_Type;
      variant    : constant String := HT.USS (rec.port_variant);
      page       : constant String := www_site & "/bucket_" & rec.bucket & "/" & nbase & "/" &
                                      variant & "/index.html";
      work_dir   : constant String := workzone & "/" & nbase;
      dossier    : constant String := calc_dossier;
   begin
      OPS.parse_and_transform_buildsheet (specification => thespec,
                                          successful    => successful,
                                          buildsheet    => dossier,
                                          variant       => variant,
                                          portloc       => work_dir,
                                          excl_targets  => False,
                                          avoid_dialog  => True,
                                          for_webpage   => True,
                                          sysrootver    => sysrootver);
      if successful then
         begin
            FOP.mkdirp_from_filename (page);
            TIO.Create (File => html_page,
                        Mode => TIO.Out_File,
                        Name => page);

            WEB.produce_page (specs   => thespec,
                              variant => variant,
                              dossier => html_page,
                              portdir => work_dir,
                              blocked => blocked_text_block (port),
                              created => cdatetime,
                              changed => mdatetime,
                              devscan => True);

            REP.clear_workzone_directory (nbase);
            TIO.Close (html_page);
            return True;
         exception
            when issue : others =>
               if TIO.Is_Open (html_page) then
                  TIO.Close (html_page);
               end if;
               TIO.Put_Line ("WWW: Failed to create " & page);
         end;
      else
         TIO.Put_Line ("WWW: Failed to parse " & dossier);
      end if;
      return False;
   end generate_single_page;


   --------------------------------------------------------------------------------------------
   --  generate_catalog_index
   --------------------------------------------------------------------------------------------
   function generate_catalog_index
     (www_site : String;
      crate    : dates_crate.Map;
      catcrate : catalog_crate.Set) return Boolean
   is
      page       : constant String := www_site & "/index.html";
      successful : Boolean;
      html_page  : TIO.File_Type;
   begin
      TIO.Create (File => html_page,
                  Mode => TIO.Out_File,
                  Name => page);
      successful := WEB.generate_catalog_index (html_page, catalog_row_block (crate, catcrate));
      TIO.Close (html_page);
      return successful;
   exception
      when issue : others =>
         if TIO.Is_Open (html_page) then
            TIO.Close (html_page);
         end if;
         return False;
   end generate_catalog_index;


   --------------------------------------------------------------------------------------------
   --  serially_generate_web_pages
   --------------------------------------------------------------------------------------------
   procedure serially_generate_web_pages
     (www_site   : String;
      sysrootver : sysroot_characteristics;
      success    : out Boolean)
   is
      procedure set_timestamps (index : port_index);

      all_good   : Boolean := True;
      workzone   : constant String := REP.get_workzone_path;
      conspiracy : constant String := HT.USS (PM.configuration.dir_conspiracy);
      unkindness : constant String := HT.USS (PM.configuration.dir_unkindness);
      crate      : dates_crate.Map;
      catcrate   : catalog_crate.Set;
      cdatetime  : CAL.Time;
      mdatetime  : CAL.Time;

      procedure set_timestamps (index : port_index)
      is
         key : HT.Text := all_ports (index).port_namebase;
      begin
         if crate.Contains (key) then
            cdatetime := crate.Element (key).creation;
            mdatetime := crate.Element (key).lastmod;
         else
            cdatetime := CAL.Time_Of (1970, 1, 1);
            mdatetime := cdatetime;
         end if;
      end set_timestamps;
   begin
      for x in 0 .. last_port loop
         store_port_dependencies (port       => x,
                                  conspiracy => conspiracy,
                                  unkindness => unkindness,
                                  sysrootver => sysrootver);
      end loop;
      iterate_reverse_deps;
      scan_port_dates (conspiracy, crate, catcrate);
      REP.launch_workzone;
      for x in 0 .. last_port loop
         set_timestamps (x);
         if not generate_single_page (port       => x,
                                      workzone   => workzone,
                                      www_site   => www_site,
                                      conspiracy => conspiracy,
                                      unkindness => unkindness,
                                      cdatetime  => cdatetime,
                                      mdatetime  => mdatetime,
                                      sysrootver => sysrootver)
         then
            all_good := False;
         end if;
      end loop;
      REP.destroy_workzone;
      if all_good then
         if generate_catalog_index (www_site, crate, catcrate) then
            success := True;
            return;
         end if;
      end if;
      success := False;
   end serially_generate_web_pages;


   --------------------------------------------------------------------------------------------
   --  scan_port_dates
   --------------------------------------------------------------------------------------------
   procedure scan_port_dates
     (conspiracy : String;
      crate      : in out dates_crate.Map;
      catcrate   : in out catalog_crate.Set)
   is
      package lastmod_crate is new CON.Hashed_Maps
        (Key_Type        => HT.Text,
         Element_Type    => disktype,
         Hash            => port_hash,
         Equivalent_Keys => HT.equivalent);

      procedure build_up_catcrate (index : port_index);

      tempstore : lastmod_crate.Map;

      procedure build_up_catcrate (index : port_index)
      is
         tempkey : HT.Text := all_ports (index).port_namebase;
         newrec  : catalog_record;
      begin
         newrec.origin := HT.SUS (get_port_variant (index));
         if tempstore.Contains (tempkey) then
            newrec.lastmod64 := tempstore.Element (tempkey);
         else
            newrec.lastmod64 := 205329600;  --  dummy: USA bicentennial
         end if;
         catcrate.Insert (newrec);
      end build_up_catcrate;

   begin
      crate.Clear;
      declare
         filename : constant String := conspiracy & "/" & port_dates;
         contents : constant String := FOP.get_file_contents (filename);
         markers  : HT.Line_Markers;
      begin
         HT.initialize_markers (contents, markers);
         loop
            exit when not HT.next_line_present (contents, markers);
            declare
               line   : constant String := HT.extract_line (contents, markers);
               key    : constant String := HT.specific_field (line, 1);
               date1  : constant String := HT.specific_field (line, 2);
               date2  : constant String := HT.specific_field (line, 3);
               keytxt : HT.Text := HT.SUS (key);
               newrec : port_dates_record;
            begin
               newrec.creation  := UTL.convert_unixtime (date1);
               newrec.lastmod   := UTL.convert_unixtime (date2);
               crate.Insert (keytxt, newrec);
               tempstore.Insert (keytxt, disktype'Value (date2));
            exception
               when others => null;
            end;
         end loop;
         for x in 0 .. last_port loop
            build_up_catcrate (x);
         end loop;
      exception
         when issue : others =>
            TIO.Put_Line ("WARNING: Failed to ingest " & port_dates & " file");
      end;
   end scan_port_dates;


   --------------------------------------------------------------------------------------------
   --  "<" for catalog crate ordered sets
   --------------------------------------------------------------------------------------------
   function "<" (L, R : catalog_record) return Boolean is
   begin
      if L.lastmod64 = R.lastmod64 then
         return HT.SU.">" (R.origin, L.origin);
      end if;
      return L.lastmod64 > R.lastmod64;
   end "<";


   --------------------------------------------------------------------------------------------
   --  catalog_row_block
   --------------------------------------------------------------------------------------------
   function catalog_row_block
     (crate    : dates_crate.Map;
      catcrate : catalog_crate.Set) return String
   is
      procedure scan (position : catalog_crate.Cursor);
      function get_lastmod (index : port_index) return String;
      function Q (value : String; first : Boolean := False) return String;

      result : HT.Text;
      counter : Positive := 1;

      function get_lastmod (index : port_index) return String
      is
         key       : HT.Text := all_ports (index).port_namebase;
         mdatetime : CAL.Time;
      begin
         if crate.Contains (key) then
            mdatetime := crate.Element (key).lastmod;
         else
            mdatetime := CAL.Time_Of (1970, 1, 1);
         end if;
         return HT.substring (LOG.timestamp (mdatetime, True), 0, 4);
      end get_lastmod;

      function Q (value : String; first : Boolean := False) return String is
      begin
         if first then
            return LAT.Quotation & value & LAT.Quotation;
         else
            return LAT.Comma & LAT.Quotation & value & LAT.Quotation;
         end if;
      end Q;

      procedure scan (position : catalog_crate.Cursor)
      is
         keytext : HT.Text renames catalog_crate.Element (position).origin;
         target  : port_index := ports_keys.Element (keytext);
         origin  : constant String := get_port_variant (target);
         pkgver  : constant String := HT.USS (all_ports (target).pkgversion);
         bucket  : constant String := all_ports (target).bucket;
         tstamp  : constant String := get_lastmod (target);
         sindex  : constant String := HT.int2str (counter);
         tagline : constant String := HT.replace_all (HT.USS (all_ports (target).ignore_reason),
                                                      LAT.Quotation, LAT.Apostrophe);
      begin
         HT.SU.Append (result, LAT.HT & "row_assy(" & Q (sindex, True) & Q (bucket) &
                         Q (origin) & Q (pkgver) & Q (tagline) & Q (tstamp) & ");" & LAT.LF);
         counter := counter + 1;
      end scan;

   begin
      catcrate.Iterate (scan'Access);
      return (HT.USS (result));
   exception
      when issue : others =>
         TIO.Put_Line ("catalog_row_block: " & Ada.Exceptions.Exception_Message (issue));
         return (HT.USS (result));
   end catalog_row_block;

end PortScan.Scan;
