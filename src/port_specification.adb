--  This file is covered by the Internet Software Consortium (ISC) License
--  Reference: ../License.txt

with Definitions; use Definitions;
with Utilities;
with Ada.Text_IO;
with Ada.Characters.Latin_1;

package body Port_Specification is

   package UTL renames Utilities;
   package TIO renames Ada.Text_IO;
   package LAT renames Ada.Characters.Latin_1;

   --------------------------------------------------------------------------------------------
   --  initialize
   --------------------------------------------------------------------------------------------
   procedure initialize (specs : out Portspecs) is
   begin
      specs.namebase     := HT.blank;
      specs.version      := HT.blank;
      specs.revision     := 0;
      specs.epoch        := 0;
      specs.keywords.Clear;
      specs.variants.Clear;
      specs.taglines.Clear;
      specs.homepage     := HT.blank;
      specs.contacts.Clear;
      specs.dl_sites.Clear;
      specs.distfiles.Clear;
      specs.dist_subdir := HT.blank;
      specs.df_index.Clear;
      specs.subpackages.Clear;
      specs.ops_avail.Clear;
      specs.ops_standard.Clear;
      specs.variantopts.Clear;
      specs.options_on.Clear;
      specs.exc_opsys.Clear;
      specs.inc_opsys.Clear;
      specs.exc_arch.Clear;
      specs.extract_only.Clear;
      specs.extract_zip.Clear;
      specs.extract_lha.Clear;
      specs.extract_7z.Clear;
      specs.extract_dirty.Clear;
      specs.extract_head.Clear;
      specs.extract_tail.Clear;
      specs.distname     := HT.blank;

      specs.skip_build   := False;
      specs.skip_install := False;
      specs.destdir_env  := False;
      specs.single_job   := False;
      specs.build_wrksrc := HT.blank;
      specs.makefile     := HT.blank;
      specs.destdirname  := HT.blank;
      specs.make_env.Clear;
      specs.make_args.Clear;
      specs.build_target.Clear;
      specs.cflags.Clear;
      specs.cxxflags.Clear;
      specs.cppflags.Clear;
      specs.ldflags.Clear;
      specs.optimizer_lvl := 2;

      specs.make_targets.Clear;

      specs.last_set := so_initialized;
   end initialize;


   --------------------------------------------------------------------------------------------
   --  set_single_string
   --------------------------------------------------------------------------------------------
   procedure set_single_string
     (specs : in out Portspecs;
      field : spec_field;
      value : String)
   is
      procedure verify_entry_is_post_options;

      text_value : HT.Text := HT.SUS (value);

      procedure verify_entry_is_post_options is
      begin
         if spec_order'Pos (specs.last_set) < spec_order'Pos (so_opts_std) then
            raise misordered with field'Img;
         end if;
      end verify_entry_is_post_options;
   begin
      if contains_nonquoted_spaces (value) then
         raise contains_spaces;
      end if;
      case field is
         when sp_namebase =>
            if specs.last_set /= so_initialized then
               raise misordered with field'Img;
            end if;
            specs.namebase := text_value;
            specs.last_set := so_namebase;
         when sp_version =>
            if specs.last_set /= so_namebase then
               raise misordered with field'Img;
            end if;
            specs.version := text_value;
            specs.last_set := so_version;
         when sp_homepage =>
            if specs.last_set /= so_taglines then
               raise misordered with field'Img;
            end if;
            if value /= homepage_none and then
              not HT.leads (value, "http://") and then
              not HT.leads (value, "https://")
            then
               raise wrong_value with "Must be '" & homepage_none
                 & "' or valid URL starting with http:// or https://";
            end if;
            specs.homepage := text_value;
            specs.last_set := so_homepage;
         when sp_distsubdir =>
            if specs.last_set /= so_distfiles and then
              specs.last_set /= so_contacts
            then
               raise misordered with field'Img;
            end if;
            specs.dist_subdir := text_value;
            specs.last_set := so_distsubdir;
         when sp_distname =>
            verify_entry_is_post_options;
            specs.distname := text_value;
         when sp_build_wrksrc =>
            verify_entry_is_post_options;
            specs.build_wrksrc := text_value;
         when sp_makefile =>
            verify_entry_is_post_options;
            specs.makefile := text_value;
         when sp_destdirname =>
            verify_entry_is_post_options;
            specs.destdirname := text_value;
         when others =>
            raise wrong_type with field'Img;
      end case;

   end set_single_string;


   --------------------------------------------------------------------------------------------
   --  append_list
   --------------------------------------------------------------------------------------------
   procedure append_list
     (specs : in out Portspecs;
      field : spec_field;
      value : String)
   is
      procedure verify_entry_is_post_options;
      procedure verify_df_index;
      procedure verify_special_exraction;

      text_value : HT.Text := HT.SUS (value);

      procedure verify_entry_is_post_options is
      begin
         if spec_order'Pos (specs.last_set) < spec_order'Pos (so_opts_std) then
            raise misordered with field'Img;
         end if;
      end verify_entry_is_post_options;

      procedure verify_df_index is
      begin
         if not specs.dist_index_is_valid (value) then
            raise wrong_value with "distfile index '" & value & "' is not valid";
         end if;
      end verify_df_index;

      procedure verify_special_exraction is
      begin
         if specs.extract_zip.Contains (text_value) or else
           specs.extract_7z.Contains (text_value)  or else
           specs.extract_lha.Contains (text_value)
         then
            raise dupe_list_value with value;
         end if;
      end verify_special_exraction;
   begin
      if contains_nonquoted_spaces (value) then
         raise contains_spaces;
      end if;
      case field is
         when sp_keywords =>
            if specs.last_set /= so_keywords and then
              specs.last_set /= so_epoch and then
              specs.last_set /= so_revision and then
              specs.last_set /= so_version
            then
               raise misordered with field'Img;
            end if;
            if not keyword_is_valid (value) then
               raise wrong_value with "Keyword '" & value & "' is not recognized";
            end if;
            if specs.keywords.Contains (text_value) then
               raise dupe_list_value with value;
            end if;
            specs.keywords.Append (text_value);
            specs.last_set := so_keywords;
         when sp_variants =>
            if specs.last_set /= so_variants and then
              specs.last_set /= so_keywords
            then
               raise misordered with field'Img;
            end if;
            if specs.variants.Is_Empty and then
              value /= variant_standard
            then
               raise wrong_value with "First variant must be '" & variant_standard & "'";
            end if;
            if value'Length > 15 then
               raise wrong_value with "'" & value & "' value is too long (15-char limit)";
            end if;
            if specs.variants.Contains (text_value) then
               raise dupe_list_value with value;
            end if;
            specs.variants.Append (text_value);
            specs.last_set := so_variants;
         when sp_contacts =>
            if specs.last_set /= so_contacts and then
              specs.last_set /= so_homepage
            then
               raise misordered with field'Img;
            end if;
            if not specs.all_taglines_defined then
               raise wrong_value with "Every variant must have SDESC definition.";
            end if;
            if not specs.contacts.Is_Empty then
               if specs.contacts.Contains (HT.SUS (contact_nobody)) then
                  raise wrong_value with "contact '" & contact_nobody & "' must be solitary";
               end if;
               if specs.contacts.Contains (HT.SUS (contact_automaton)) then
                  raise wrong_value with "contact '" & contact_automaton & "' must be solitary";
               end if;
               if value = contact_nobody or else value = contact_automaton then
                  raise wrong_value with "contact '" & value & "' must be solitary";
               end if;
            end if;
            if value /= contact_nobody and then
              value /= contact_automaton and then
              not (HT.contains (value, "_") and then
                   HT.contains (value, "[") and then
                   HT.contains (value, "@") and then
                   HT.contains (value, "]") and then
                  value (value'Last) = LAT.Right_Square_Bracket)
            then
               raise wrong_value with "incorrect contact format of '" & value & "'";
            end if;
            if specs.contacts.Contains (text_value) then
               raise dupe_list_value with value;
            end if;
            specs.contacts.Append (text_value);
            specs.last_set := so_contacts;
         when sp_distfiles =>
            if specs.last_set /= so_distfiles and then
              specs.last_set /= so_dl_sites
            then
               raise misordered with field'Img;
            end if;
            if specs.distfiles.Contains (text_value) then
               raise dupe_list_value with value;
            end if;
            if not HT.contains (value, ":") then
               raise wrong_value with "No download group prefix present in distfile";
            end if;
            specs.distfiles.Append (text_value);
            specs.last_set := so_distfiles;
            declare
               group_index : String := HT.int2str (Integer (specs.distfiles.Length));
            begin
               specs.establish_group (sp_ext_head, group_index);
               specs.establish_group (sp_ext_tail, group_index);
            end;
         when sp_df_index =>
            if specs.last_set /= so_df_index and then
              specs.last_set /= so_distsubdir and then
              specs.last_set /= so_distfiles
            then
               raise misordered with field'Img;
            end if;
            if specs.df_index.Contains (text_value) then
               raise dupe_list_value with value;
            end if;
            verify_df_index;
            specs.df_index.Append (text_value);
            specs.last_set := so_df_index;
         when sp_opts_avail =>
            if specs.last_set /= so_opts_avail and then
              specs.last_set /= so_subpackages
            then
               raise misordered with field'Img;
            end if;
            if specs.ops_avail.Contains (text_value) then
               raise dupe_list_value with value;
            end if;
            if value = options_none then
               if not specs.ops_avail.Is_Empty then
                  raise wrong_value with "'" & options_none & "' must be set first and alone";
               end if;
            else
               if HT.uppercase (value) /= value then
                  raise wrong_value with "option value '" & value & "' is not capitalized";
               end if;
            end if;
            if value'Length > 14 then
               raise wrong_value with "'" & value & "' name is too long (14-char limit)";
            end if;
            specs.ops_avail.Append (text_value);
            specs.last_set := so_opts_avail;
         when sp_opts_standard =>
            if specs.last_set /= so_opts_std and then
              specs.last_set /= so_opts_avail
            then
               raise misordered with field'Img;
            end if;
            if specs.ops_standard.Contains (text_value) then
               raise dupe_list_value with value;
            end if;
            if value = options_none then
               if not specs.ops_standard.Is_Empty then
                  raise wrong_value with "'" & options_none & "' must be set first and alone";
               end if;
            else
               if not specs.ops_avail.Contains (text_value) then
                  raise wrong_value with "'" & value & "' must be present in OPTIONS_AVAILABLE";
               end if;
            end if;
            specs.ops_standard.Append (text_value);
            specs.last_set := so_opts_std;
         when sp_exc_opsys =>
            verify_entry_is_post_options;
            if not specs.inc_opsys.Is_Empty then
               raise wrong_value with "NOT_FOR_OPSYS can't be used after ONLY_FOR_OPSYS";
            end if;
            if specs.exc_opsys.Contains (text_value) then
               raise dupe_list_value with value;
            end if;
            if not UTL.valid_lower_opsys (value) then
               raise wrong_value with "opsys '" & value & "' is not valid.";
            end if;
            specs.exc_opsys.Append (text_value);
         when sp_inc_opsys =>
            verify_entry_is_post_options;
            if not specs.exc_opsys.Is_Empty then
               raise wrong_value with "ONLY_FOR_OPSYS can't be used after NOT_FOR_OPSYS";
            end if;
            if specs.inc_opsys.Contains (text_value) then
               raise dupe_list_value with value;
            end if;
            if not UTL.valid_lower_opsys (value) then
               raise wrong_value with "opsys '" & value & "' is not valid.";
            end if;
            specs.inc_opsys.Append (text_value);
         when sp_exc_arch =>
            verify_entry_is_post_options;
            if specs.exc_arch.Contains (text_value) then
               raise dupe_list_value with value;
            end if;
            if not UTL.valid_cpu_arch (value) then
               raise wrong_value with "'" & value & "' is not a valid architecture.";
            end if;
            specs.exc_arch.Append (text_value);
         when sp_ext_only =>
            verify_entry_is_post_options;
            verify_df_index;
            if specs.extract_only.Contains (text_value) then
               raise dupe_list_value with value;
            end if;
            specs.extract_only.Append (text_value);
         when sp_ext_7z =>
            verify_entry_is_post_options;
            verify_df_index;
            verify_special_exraction;
            specs.extract_7z.Append (text_value);
         when sp_ext_lha =>
            verify_entry_is_post_options;
            verify_df_index;
            verify_special_exraction;
            specs.extract_lha.Append (text_value);
         when sp_ext_zip =>
            verify_entry_is_post_options;
            verify_df_index;
            verify_special_exraction;
            specs.extract_zip.Append (text_value);
         when sp_ext_dirty =>
            verify_entry_is_post_options;
            verify_df_index;
            if specs.extract_dirty.Contains (text_value) then
               raise dupe_list_value with value;
            end if;
            specs.extract_dirty.Append (text_value);
         when sp_make_args =>
            verify_entry_is_post_options;
            specs.make_args.Append (text_value);
         when sp_make_env =>
            verify_entry_is_post_options;
            specs.make_env.Append (text_value);
         when sp_build_target =>
            verify_entry_is_post_options;
            specs.build_target.Append (text_value);
         when sp_cflags =>
            verify_entry_is_post_options;
            specs.cflags.Append (text_value);
         when sp_cxxflags =>
            verify_entry_is_post_options;
            specs.cxxflags.Append (text_value);
         when sp_cppflags =>
            verify_entry_is_post_options;
            specs.cppflags.Append (text_value);
         when sp_ldflags =>
            verify_entry_is_post_options;
            specs.ldflags.Append (text_value);
         when others =>
            raise wrong_type with field'Img;
      end case;

   end append_list;


   --------------------------------------------------------------------------------------------
   --  append_array
   --------------------------------------------------------------------------------------------
   procedure establish_group
     (specs : in out Portspecs;
      field : spec_field;
      group : String)
   is
      text_group : HT.Text := HT.SUS (group);
      initial_rec : group_list;
   begin
      if HT.contains (S => group, fragment => " ") then
         raise contains_spaces;
      end if;
      initial_rec.group := text_group;
      case field is
         when sp_dl_groups =>
            if specs.last_set /= so_dl_groups and then
              specs.last_set /= so_contacts
            then
               raise misordered with field'Img;
            end if;
            if specs.dl_sites.Is_Empty then
               if group /= dlgroup_main and then
                 group /= dlgroup_none
               then
                  raise wrong_value with "First download group must be '" & dlgroup_main &
                    "' or '" & dlgroup_none & "'";
               end if;
            else
               if group = dlgroup_none then
                  raise wrong_value with "download group '" & group &
                    "' follows group definition";
               end if;
               if group = dlgroup_main then
                  raise wrong_value with "'" & group & "' download group must be " &
                    "defined earlier";
               end if;
            end if;
            if group'Length > 15 then
               raise wrong_value with "'" & group & "' value is too long (15-char limit)";
            end if;
            if specs.dl_sites.Contains (text_group) then
               raise dupe_list_value with group;
            end if;
            specs.dl_sites.Insert (text_group, initial_rec);
            specs.last_set := so_dl_groups;
         when sp_subpackages =>
            --  variant, order, length and uniqueness already checked
            --  don't updatee last_set either
            specs.subpackages.Insert (text_group, initial_rec);
         when sp_vopts =>
            --  variant, order, length and uniqueness already checked
            --  don't updatee last_set either
            specs.variantopts.Insert (text_group, initial_rec);
         when sp_ext_head =>
            specs.extract_head.Insert (text_group, initial_rec);
         when sp_ext_tail =>
            specs.extract_tail.Insert (text_group, initial_rec);
         when sp_makefile_targets =>
            specs.make_targets.Insert (text_group, initial_rec);
         when sp_options_on =>
            specs.options_on.Insert (text_group, initial_rec);
         when others =>
            raise wrong_type with field'Img;
      end case;
   end establish_group;


   --------------------------------------------------------------------------------------------
   --  append_array
   --------------------------------------------------------------------------------------------
   procedure append_array
     (specs : in out Portspecs;
      field : spec_field;
      key   : String;
      value : String;
      allow_spaces : Boolean)
   is
      procedure grow (Key : HT.Text; Element : in out group_list);
      procedure verify_entry_is_post_options;

      text_key   : HT.Text := HT.SUS (key);
      text_value : HT.Text := HT.SUS (value);

      procedure grow (Key : HT.Text; Element : in out group_list) is
      begin
         Element.list.Append (text_value);
      end grow;

      procedure verify_entry_is_post_options is
      begin
         if spec_order'Pos (specs.last_set) < spec_order'Pos (so_opts_std) then
            raise misordered with field'Img;
         end if;
      end verify_entry_is_post_options;
   begin
      if not allow_spaces and then
        HT.contains (S => value, fragment => " ")
      then
         raise contains_spaces;
      end if;
      case field is
         when sp_taglines =>
            if specs.last_set /= so_taglines and then
              specs.last_set /= so_variants
            then
               raise misordered with field'Img;
            end if;
            if specs.taglines.Contains (text_key) then
               raise dupe_spec_key with key & " (SDESC)";
            end if;
            --  SDESC requirements checked by caller.  Assume string is legal.
            specs.taglines.Insert (Key      => text_key,
                                   New_Item => text_value);
            specs.last_set := so_taglines;
         when sp_dl_sites =>
            if specs.last_set /= so_dl_sites and then
              specs.last_set /= so_dl_groups
            then
               raise misordered with field'Img;
            end if;
            if not specs.dl_sites.Contains (text_key) then
               raise missing_group with key;
            end if;
            if specs.dl_sites.Element (text_key).list.Contains (text_value) then
               raise dupe_list_value with value;
            end if;
            specs.dl_sites.Update_Element (Position => specs.dl_sites.Find (text_key),
                                           Process  => grow'Access);
            specs.last_set := so_dl_sites;
         when sp_subpackages =>
            if spec_order'Pos (specs.last_set) > spec_order'Pos (so_subpackages) or else
              spec_order'Pos (specs.last_set) < spec_order'Pos (so_dl_groups)
            then
               raise misordered with field'Img;
            end if;
            if not specs.subpackages.Contains (text_key) then
               raise missing_group with key;
            end if;
            if specs.subpackages.Element (text_key).list.Contains (text_value) then
               raise dupe_list_value with value;
            end if;
            specs.subpackages.Update_Element (Position => specs.subpackages.Find (text_key),
                                              Process  => grow'Access);
            specs.last_set := so_subpackages;
         when sp_vopts =>
            if specs.last_set /= so_vopts and then
              specs.last_set /= so_opts_std
            then
               raise misordered with field'Img;
            end if;
            if not specs.variantopts.Contains (text_key) then
               raise missing_group with key;
            end if;
            declare
               strlast : Natural;
               WON     : HT.Text;
               WOFF    : HT.Text;
            begin
               if HT.trails (value, "=ON") then
                  strlast := value'Last - 3;
                  WON     := text_value;
                  WOFF    := HT.SUS (value (value'First .. strlast) & "=OFF");
               elsif HT.trails (value, "=OFF") then
                  strlast := value'Last - 4;
                  WOFF    := text_value;
                  WON     := HT.SUS (value (value'First .. strlast) & "=ON");
               else
                  raise wrong_value with "'" & value & "' doesn't end in '=ON' or '=OFF'";
               end if;
               if specs.variantopts.Element (text_key).list.Contains (WON) or else
                 specs.variantopts.Element (text_key).list.Contains (WOFF)
               then
                  raise dupe_list_value with value;
               end if;
               if not specs.ops_avail.Contains (HT.SUS (value (value'First .. strlast))) then
                  raise wrong_value with "'" & value (value'First .. strlast)
                    & "' was not present in OPTIONS_AVAILABLE";
               end if;
            end;
            specs.variantopts.Update_Element (Position => specs.variantopts.Find (text_key),
                                              Process  => grow'Access);
            specs.last_set := so_vopts;
         when sp_ext_head =>
            verify_entry_is_post_options;
            if not specs.extract_head.Contains (text_key) then
               raise missing_group with key;
            end if;
            if not specs.extract_head.Element (text_key).list.Is_Empty then
               raise wrong_value with "Only 1 entry is allowed";
            end if;
            specs.extract_head.Update_Element (Position => specs.extract_head.Find (text_key),
                                               Process  => grow'Access);
         when sp_ext_tail =>
            verify_entry_is_post_options;
            if not specs.extract_tail.Contains (text_key) then
               raise missing_group with key;
            end if;
            if not specs.extract_tail.Element (text_key).list.Is_Empty then
               raise wrong_value with "Only 1 entry is allowed";
            end if;
            specs.extract_tail.Update_Element (Position => specs.extract_tail.Find (text_key),
                                               Process  => grow'Access);
         when sp_makefile_targets =>
            verify_entry_is_post_options;
            if not specs.make_targets.Contains (text_key) then
               raise missing_group with key;
            end if;
            specs.make_targets.Update_Element (Position => specs.make_targets.Find (text_key),
                                               Process  => grow'Access);
         when sp_options_on =>
            verify_entry_is_post_options;
            if not specs.options_on.Contains (text_key) then
               --  Group already validated, so create if it dosn't exist
               specs.establish_group (sp_options_on, key);
               --  "all" must exist if non-"all" keys are used though
               if not specs.options_on.Contains (HT.SUS (options_all)) then
                  specs.establish_group (sp_options_on, options_all);
               end if;
            end if;
            if not specs.valid_OPT_ON_value (key, value) then
               raise wrong_value with "OPT_ON value '" & value &
                 "' either doesn't match option list, is present in 'all' section, " &
                 "or it is misformatted";
            end if;
            specs.options_on.Update_Element (Position => specs.options_on.Find (text_key),
                                             Process  => grow'Access);
         when others =>
            raise wrong_type with field'Img;
      end case;
   end append_array;


   --------------------------------------------------------------------------------------------
   --  set_natural_integer
   --------------------------------------------------------------------------------------------
   procedure set_natural_integer
     (specs : in out Portspecs;
      field : spec_field;
      value : Natural) is
      procedure verify_entry_is_post_options;
      procedure verify_entry_is_post_options is
      begin
         if spec_order'Pos (specs.last_set) < spec_order'Pos (so_opts_std) then
            raise misordered with field'Img;
         end if;
      end verify_entry_is_post_options;
   begin
      case field is
         when sp_revision =>
            if specs.last_set /= so_version then
               raise misordered with field'Img;
            end if;
            specs.revision := value;
            specs.last_set := so_revision;
         when sp_epoch =>
            if specs.last_set /= so_revision and then
              specs.last_set /= so_version
            then
               raise misordered with field'Img;
            end if;
            specs.epoch := value;
            specs.last_set := so_epoch;
         when sp_opt_level =>
            verify_entry_is_post_options;
            if value > 3 then
               raise wrong_value with "OPTIMIZER_LEVEL is limited to 3";
            end if;
            specs.optimizer_lvl := value;
         when others =>
            raise wrong_type with field'Img;
      end case;
   end set_natural_integer;


   --------------------------------------------------------------------------------------------
   --  set_boolean
   --------------------------------------------------------------------------------------------
   procedure set_boolean
     (specs : in out Portspecs;
      field : spec_field;
      value : Boolean) is
   begin
      case field is
         when sp_skip_build =>
            specs.skip_build := value;
         when sp_destdir_env =>
            specs.destdir_env := value;
         when sp_single_job =>
            specs.single_job := value;
         when sp_skip_install =>
            specs.skip_install := value;
         when others =>
            raise wrong_type with field'Img;
      end case;
   end set_boolean;


   --------------------------------------------------------------------------------------------
   --  variant_exists
   --------------------------------------------------------------------------------------------
   function variant_exists (specs : Portspecs; variant : String) return Boolean is
   begin
      return specs.variants.Contains (Item => HT.SUS (variant));
   end variant_exists;


   --------------------------------------------------------------------------------------------
   --  option_exists
   --------------------------------------------------------------------------------------------
   function option_exists (specs : Portspecs; option : String) return Boolean
   is
      option_text : HT.Text := HT.SUS (option);
   begin
      if option = "" then
         return False;
      end if;
      return specs.ops_avail.Contains (option_text);
   end option_exists;


   --------------------------------------------------------------------------------------------
   --  group_exists
   --------------------------------------------------------------------------------------------
   function group_exists
     (specs : Portspecs;
      field : spec_field;
      group : String) return Boolean
   is
      text_group : HT.Text := HT.SUS (group);
   begin
      case field is
         when sp_dl_sites =>
            return specs.dl_sites.Contains (text_group);
         when others => return False;
      end case;
   end group_exists;


   --------------------------------------------------------------------------------------------
   --  option_current_setting
   --------------------------------------------------------------------------------------------
   function option_current_setting (specs : Portspecs; option : String) return Boolean is
   begin
      if not specs.option_exists (option) then
         raise invalid_option with option;
      end if;
      --  TO-DO: return current setting of option
      return False;
   end option_current_setting;


   --------------------------------------------------------------------------------------------
   --  all_taglines_defined
   --------------------------------------------------------------------------------------------
   function all_taglines_defined (specs : Portspecs) return Boolean
   is
      procedure check (position : string_crate.Cursor);

      all_present : Boolean := True;

      procedure check (position : string_crate.Cursor)
      is
         variant : HT.Text := string_crate.Element (position);
      begin
         if not specs.taglines.Contains (variant) then
            all_present := False;
         end if;
      end check;
   begin
      specs.variants.Iterate (Process => check'Access);
      return all_present;
   end all_taglines_defined;


   --------------------------------------------------------------------------------------------
   --  check_variants
   --------------------------------------------------------------------------------------------
   function check_variants (specs : Portspecs) return String
   is
      procedure check (position : string_crate.Cursor);
      procedure check_option (position : string_crate.Cursor);

      result  : HT.Text := HT.blank;
      variant : HT.Text;

      --  OPTIONS_AVAILABLE process
      procedure check_option (position : string_crate.Cursor)
      is
         option : HT.Text := string_crate.Element (position);
      begin
         if HT.IsBlank (result) then
            declare
               step  : String  := HT.USS (option);
               WON   : HT.Text := HT.SUS (step & "=ON");
               WOFF  : HT.Text := HT.SUS (step & "=OFF");
            begin
               if not specs.variantopts.Element (variant).list.Contains (WON) and then
                 not specs.variantopts.Element (variant).list.Contains (WOFF)
               then
                  result := HT.SUS (HT.USS (variant) & ":" & step);
               end if;
            end;
         end if;
      end check_option;

      --  variant process
      procedure check (position : string_crate.Cursor) is
      begin
         variant := string_crate.Element (position);
         if HT.IsBlank (result) then
            if HT.USS (variant) /= variant_standard then

               --  It's impossible that variantopts doesn't have variant, so don't test
               specs.ops_avail.Iterate (Process => check_option'Access);
            end if;
         end if;
      end check;
   begin
      specs.variants.Iterate (Process => check'Access);
      return HT.USS (result);
   end check_variants;


   --------------------------------------------------------------------------------------------
   --  contains_nonquoted_spaces
   --------------------------------------------------------------------------------------------
   function contains_nonquoted_spaces (word : String) return Boolean
   is
      mask    : String  := word;
      Qopened : Boolean := False;
   begin
      for x in mask'Range loop
         if mask (x) = LAT.Quotation then
            Qopened := not Qopened;
         elsif mask (x) = LAT.Space then
            if Qopened then
               mask (x) := 'X';
            end if;
         end if;
      end loop;
      return HT.contains (S => mask, fragment => " ");
   end contains_nonquoted_spaces;


   --------------------------------------------------------------------------------------------
   --  adjust_defaults_port_parse
   --------------------------------------------------------------------------------------------
   procedure adjust_defaults_port_parse (specs : in out Portspecs)
   is
      procedure grow (Key : HT.Text; Element : in out group_list);

      empty_comment : HT.Text := HT.SUS ("# empty");

      procedure grow (Key : HT.Text; Element : in out group_list) is
      begin
         Element.list.Append (empty_comment);
      end grow;
   begin
      for X in Integer range 1 .. Integer (specs.extract_head.Length) loop
         declare
            N : HT.Text := HT.SUS (HT.int2str (X));
         begin
            if not specs.extract_head.Element (N).list.Is_Empty and then
              specs.extract_tail.Element (N).list.Is_Empty
            then
               specs.extract_tail.Update_Element (Position => specs.extract_tail.Find (N),
                                                  Process  => grow'Access);
            else
               if not specs.extract_tail.Element (N).list.Is_Empty and then
                 specs.extract_head.Element (N).list.Is_Empty
               then
                  specs.extract_head.Update_Element (Position => specs.extract_head.Find (N),
                                                     Process  => grow'Access);
               end if;
            end if;
         end;
      end loop;
      if specs.df_index.Is_Empty then
         specs.df_index.Append (HT.SUS ("1"));
      end if;
   end adjust_defaults_port_parse;


   --------------------------------------------------------------------------------------------
   --  dist_index_is_valid
   --------------------------------------------------------------------------------------------
   function dist_index_is_valid (specs : Portspecs; test_index : String) return Boolean
   is
      mynum : Integer := Integer'Value (test_index);
   begin
      return (mynum >= 1 and then mynum <= Integer (specs.distfiles.Length));
   exception
      when Constraint_Error =>
         return False;
   end dist_index_is_valid;


   --------------------------------------------------------------------------------------------
   --  valid_OPT_ON_value
   --------------------------------------------------------------------------------------------
   function valid_OPT_ON_value (specs : Portspecs;
                                key   : String;
                                word  : String) return Boolean
   is
      function looks_like_release (wrkstr : String) return Boolean;
      function looks_like_release (wrkstr : String) return Boolean is
      begin
         for X in wrkstr'Range loop
            case wrkstr (X) is
               when '0' .. '9' | '.' => null;
               when others => return False;
            end case;
         end loop;
         return True;
      end looks_like_release;
   begin
      if key = options_all or else
        UTL.valid_cpu_arch (key)
      then
         --  "all" and arch types Limited to existing options
         return specs.option_exists (word);
      end if;

      --  Note: "all" must come first and nothing following can define options that are
      --  already defined in "all".
      if specs.option_exists (word) then
         return not specs.option_present_in_OPT_ON_all (word);
      end if;

      declare
         P2_1 : String := HT.part_1 (word, "/");
         P2_2 : String := HT.part_2 (word, "/");
      begin
         if P2_2'Length = 0 then
            return False;
         end if;
         if specs.option_exists (P2_1) then
            if specs.option_present_in_OPT_ON_all (P2_1) then
               return False;
            end if;
         else
            return False;
         end if;
         if HT.contains (P2_2, "/") then
            --  This is a triplet
            declare
               P3_1 : String := HT.part_1 (P2_2, "/");
               P3_2 : String := HT.part_2 (P2_2, "/");
            begin
               if P3_1 /= "" and then
                 not looks_like_release (P3_1)
               then
                  return False;
               end if;
               --  Here: P2_2 matches an option
               --        P3_1 is empty string or a release
               declare
                  num_bars   : Natural := HT.count_char (P3_2, LAT.Vertical_Line);
                  bck_marker : Natural := P3_2'First;
                  vrt_marker : Natural := bck_marker;
               begin
                  if num_bars = 0 then
                     return UTL.valid_cpu_arch (P3_2);
                  end if;
                  if num_bars = 1 then
                     return UTL.valid_cpu_arch (HT.part_1 (P3_2, "|")) and then
                       UTL.valid_cpu_arch (HT.part_2 (P3_2, "|"));
                  end if;
                  for V in Positive range 1 .. num_bars loop
                     loop
                        exit when P3_2 (vrt_marker) = LAT.Vertical_Line;
                        vrt_marker := vrt_marker + 1;
                     end loop;
                     if not UTL.valid_cpu_arch (P3_2 (bck_marker .. vrt_marker - 1)) then
                        return False;
                     end if;
                     bck_marker := vrt_marker + 1;
                     vrt_marker := bck_marker;
                  end loop;
                  return UTL.valid_cpu_arch (P3_2 (bck_marker .. P3_2'Last));
               end;
            end;
         else
            --  Only [0-9.] allowed
            return looks_like_release (P2_2);
         end if;
      end;
   end valid_OPT_ON_value;


   --------------------------------------------------------------------------------------------
   --  option_present_in_OPT_ON_all
   --------------------------------------------------------------------------------------------
   function option_present_in_OPT_ON_all (specs : Portspecs;
                                          option_name : String) return Boolean is
   begin
      return specs.options_on.Element (HT.SUS (options_all)).list.Contains (HT.SUS (option_name));
   end option_present_in_OPT_ON_all;


   --------------------------------------------------------------------------------------------
   --  keyword_is_valid
   --------------------------------------------------------------------------------------------
   function keyword_is_valid (keyword : String) return Boolean is
   begin
      return (keyword = "accessibility" or else
              keyword = "archivers" or else
              keyword = "astro" or else
              keyword = "audio" or else
              keyword = "benchmarks" or else
              keyword = "biology" or else
              keyword = "cad" or else
              keyword = "comms" or else
              keyword = "converters" or else
              keyword = "databases" or else
              keyword = "deskutils" or else
              keyword = "devel" or else
              keyword = "dns" or else
              keyword = "editors" or else
              keyword = "emulators" or else
              keyword = "finance" or else
              keyword = "ftp" or else
              keyword = "games" or else
              keyword = "graphics" or else
              keyword = "irc" or else
              keyword = "lang" or else
              keyword = "mail" or else
              keyword = "math" or else
              keyword = "misc" or else
              keyword = "multimedia" or else
              keyword = "net" or else
              keyword = "net_im" or else
              keyword = "net_mgmt" or else
              keyword = "net_p2p" or else
              keyword = "news" or else
              keyword = "print" or else
              keyword = "raven" or else
              keyword = "science" or else
              keyword = "security" or else
              keyword = "shells" or else
              keyword = "sysutils" or else
              keyword = "textproc" or else
              keyword = "www" or else
              keyword = "x11" or else
              keyword = "x11_clocks" or else
              keyword = "x11_drivers" or else
              keyword = "x11_fm" or else
              keyword = "x11_fonts" or else
              keyword = "x11_servers" or else
              keyword = "x11_toolkits" or else
              keyword = "x11_wm" or else
              keyword = "ada" or else
              keyword = "c++" or else
              keyword = "csharp" or else
              keyword = "java" or else
              keyword = "javascript" or else
              keyword = "lisp" or else
              keyword = "perl" or else
              keyword = "php" or else
              keyword = "python" or else
              keyword = "ruby" or else
              keyword = "scheme" or else
              keyword = "Arabic" or else
              keyword = "Chinese" or else
              keyword = "French" or else
              keyword = "German" or else
              keyword = "Italian" or else
              keyword = "Japanese" or else
              keyword = "Russian" or else
              keyword = "Spanish" or else
              keyword = "Vietnamese");
   end keyword_is_valid;


   --------------------------------------------------------------------------------------------
   --  dump_specification
   --------------------------------------------------------------------------------------------
   procedure dump_specification (specs : Portspecs)
   is
      procedure print_item (position : string_crate.Cursor);
      procedure print_item (position : def_crate.Cursor);
      procedure print_line_item (position : string_crate.Cursor);
      procedure dump (position : list_crate.Cursor);
      procedure dump_target (position : list_crate.Cursor);
      procedure print_vector_list (thelabel : String; thelist : spec_field);
      procedure print_group_list  (thelabel : String; thelist : spec_field);
      procedure print_single (thelabel : String; thelist : spec_field);
      procedure print_boolean (thelabel : String; thelist : spec_field);

      array_label : Positive;

      procedure print_item (position : string_crate.Cursor)
      is
         index : Natural := string_crate.To_Index (position);
      begin
         if index > 1 then
            TIO.Put (" ");
         end if;
         TIO.Put (HT.USS (string_crate.Element (position)));
      end print_item;

      procedure print_item (position : def_crate.Cursor) is
      begin
         case array_label is
            when 1 => TIO.Put ("SDESC[");
            when others => null;
         end case;
         TIO.Put_Line (HT.USS (def_crate.Key (position)) & LAT.Right_Square_Bracket &
                         LAT.HT & LAT.HT & HT.USS (def_crate.Element (position)));
      end print_item;

      procedure print_line_item (position : string_crate.Cursor)
      is
         index : Natural := string_crate.To_Index (position);
      begin
         TIO.Put_Line (HT.USS (string_crate.Element (position)));
      end print_line_item;

      procedure dump (position : list_crate.Cursor)
      is
         NDX : String := HT.USS (list_crate.Element (position).group);
      begin
         TIO.Put ("   " & NDX);
         if NDX'Length < 5 then
            TIO.Put (LAT.HT & LAT.HT & LAT.HT);
         elsif NDX'Length < 13 then
            TIO.Put (LAT.HT & LAT.HT);
         else
            TIO.Put (LAT.HT);
         end if;
         list_crate.Element (position).list.Iterate (Process => print_item'Access);
         TIO.Put (LAT.LF);
      end dump;

      procedure dump_target (position : list_crate.Cursor)
      is
         NDX : String := HT.USS (list_crate.Element (position).group);
      begin
         TIO.Put_Line ("   " & NDX & LAT.Colon);
         list_crate.Element (position).list.Iterate (Process => print_line_item'Access);
      end dump_target;

      procedure print_vector_list (thelabel : String; thelist : spec_field)
      is
         labellen : Natural := thelabel'Length;
      begin
         TIO.Put (thelabel & LAT.Equals_Sign & LAT.HT);
         if labellen < 7 then
            TIO.Put (LAT.HT & LAT.HT);
         elsif labellen < 15 then
            TIO.Put (LAT.HT);
         end if;
         case thelist is
            when sp_exc_opsys     => specs.exc_opsys.Iterate (Process => print_item'Access);
            when sp_inc_opsys     => specs.inc_opsys.Iterate (Process => print_item'Access);
            when sp_exc_arch      => specs.exc_arch.Iterate (Process => print_item'Access);
            when sp_opts_avail    => specs.ops_avail.Iterate (Process => print_item'Access);
            when sp_opts_standard => specs.ops_standard.Iterate (Process => print_item'Access);
            when sp_df_index      => specs.df_index.Iterate (Process => print_item'Access);
            when sp_distfiles     => specs.distfiles.Iterate (Process => print_item'Access);
            when sp_contacts      => specs.contacts.Iterate (Process => print_item'Access);
            when sp_variants      => specs.variants.Iterate (Process => print_item'Access);
            when sp_keywords      => specs.keywords.Iterate (Process => print_item'Access);
            when sp_ext_only      => specs.extract_only.Iterate (Process => print_item'Access);
            when sp_ext_zip       => specs.extract_zip.Iterate (Process => print_item'Access);
            when sp_ext_7z        => specs.extract_7z.Iterate (Process => print_item'Access);
            when sp_ext_lha       => specs.extract_lha.Iterate (Process => print_item'Access);
            when sp_ext_dirty     => specs.extract_dirty.Iterate (Process => print_item'Access);
            when sp_make_args     => specs.make_args.Iterate (Process => print_item'Access);
            when sp_make_env      => specs.make_env.Iterate (Process => print_item'Access);
            when sp_build_target  => specs.build_target.Iterate (Process => print_item'Access);
            when sp_cflags        => specs.cflags.Iterate (Process => print_item'Access);
            when sp_cxxflags      => specs.cxxflags.Iterate (Process => print_item'Access);
            when sp_cppflags      => specs.cppflags.Iterate (Process => print_item'Access);
            when sp_ldflags       => specs.ldflags.Iterate (Process => print_item'Access);
            when others => null;
         end case;
         TIO.Put (LAT.LF);
      end print_vector_list;

      procedure print_group_list (thelabel : String; thelist : spec_field) is
      begin
         TIO.Put_Line (thelabel & LAT.Colon);
         case thelist is
            when sp_vopts            => specs.variantopts.Iterate (Process => dump'Access);
            when sp_options_on       => specs.options_on.Iterate (Process => dump'Access);
            when sp_subpackages      => specs.subpackages.Iterate (Process => dump'Access);
            when sp_dl_sites         => specs.dl_sites.Iterate (Process => dump'Access);
            when sp_ext_head         => specs.extract_head.Iterate (Process => dump'Access);
            when sp_ext_tail         => specs.extract_tail.Iterate (Process => dump'Access);
            when sp_makefile_targets => specs.make_targets.Iterate (Process => dump_target'Access);
            when others => null;
         end case;
      end print_group_list;

      procedure print_single (thelabel : String; thelist : spec_field)
      is
         labellen : Natural := thelabel'Length;
      begin
         TIO.Put (thelabel & LAT.Equals_Sign & LAT.HT);
         if labellen < 7 then
            TIO.Put (LAT.HT & LAT.HT);
         elsif labellen < 15 then
            TIO.Put (LAT.HT);
         end if;
         case thelist is
            when sp_namebase     => TIO.Put_Line (HT.USS (specs.namebase));
            when sp_version      => TIO.Put_Line (HT.USS (specs.version));
            when sp_revision     => TIO.Put_Line (HT.int2str (specs.revision));
            when sp_epoch        => TIO.Put_Line (HT.int2str (specs.epoch));
            when sp_opt_level    => TIO.Put_Line (HT.int2str (specs.optimizer_lvl));
            when sp_distsubdir   => TIO.Put_Line (HT.USS (specs.dist_subdir));
            when sp_distname     => TIO.Put_Line (HT.USS (specs.distname));
            when sp_build_wrksrc => TIO.Put_Line (HT.USS (specs.build_wrksrc));
            when sp_makefile     => TIO.Put_Line (HT.USS (specs.makefile));
            when sp_destdirname  => TIO.Put_Line (HT.USS (specs.destdirname));
            when sp_homepage     => TIO.Put_Line (HT.USS (specs.homepage));
            when others => null;
         end case;
      end print_single;

      procedure print_boolean (thelabel : String; thelist : spec_field)
      is
         labellen : Natural := thelabel'Length;
      begin
         TIO.Put (thelabel & LAT.Equals_Sign & LAT.HT);
         if labellen < 7 then
            TIO.Put (LAT.HT & LAT.HT);
         elsif labellen < 15 then
            TIO.Put (LAT.HT);
         end if;
         case thelist is
            when sp_skip_build     => TIO.Put_Line (specs.skip_build'Img);
            when sp_skip_install   => TIO.Put_Line (specs.skip_install'Img);
            when sp_destdir_env    => TIO.Put_Line (specs.destdir_env'Img);
            when sp_single_job     => TIO.Put_Line (specs.single_job'Img);
            when others => null;
         end case;
      end print_boolean;

   begin
      print_single      ("NAMEBASE", sp_namebase);
      print_single      ("VERSION",  sp_version);
      print_single      ("REVISION", sp_revision);
      print_single      ("EPOCH",    sp_epoch);
      print_vector_list ("KEYWORDS", sp_keywords);
      print_vector_list ("VARIANTS", sp_variants);
      array_label := 1;
      specs.taglines.Iterate (Process => print_item'Access);
      print_single      ("HOMEPAGE", sp_homepage);
      print_vector_list ("CONTACTS", sp_contacts);
      print_group_list  ("SITES", sp_dl_sites);
      print_vector_list ("DISTFILE", sp_distfiles);
      print_single      ("DIST_SUBDIR", sp_distsubdir);
      print_vector_list ("DF_INDEX", sp_df_index);
      print_group_list  ("SPKGS", sp_subpackages);
      print_vector_list ("OPTIONS_AVAILABLE", sp_opts_avail);
      print_vector_list ("OPTIONS_STANDARD", sp_opts_standard);
      print_group_list  ("VOPTS", sp_subpackages);
      print_group_list  ("OPT_ON", sp_options_on);
      print_vector_list ("ONLY_FOR_OPSYS", sp_inc_opsys);
      print_vector_list ("NOT_FOR_OPSYS", sp_exc_opsys);
      print_vector_list ("NOT_FOR_ARCH", sp_exc_arch);

      print_single      ("DISTNAME", sp_distname);
      print_vector_list ("EXTRACT_ONLY", sp_ext_only);
      print_vector_list ("EXTRACT_WITH_UNZIP", sp_ext_zip);
      print_vector_list ("EXTRACT_WITH_7Z", sp_ext_7z);
      print_vector_list ("EXTRACT_WITH_LHA", sp_ext_lha);
      print_vector_list ("EXTRACT_DIRTY", sp_ext_dirty);
      print_group_list  ("EXTRACT_HEAD", sp_ext_head);
      print_group_list  ("EXTRACT_TAIL", sp_ext_tail);

      print_boolean     ("SKIP_BUILD", sp_skip_build);
      print_boolean     ("SKIP_INSTALL", sp_skip_install);
      print_boolean     ("SINGLE_JOB", sp_single_job);
      print_boolean     ("DESTDIR_VIA_ENV", sp_destdir_env);
      print_single      ("BUILD_WRKSRC", sp_build_wrksrc);
      print_single      ("MAKEFILE", sp_makefile);
      print_single      ("DESTDIRNAME", sp_destdirname);
      print_vector_list ("MAKE_ARGS", sp_make_args);
      print_vector_list ("MAKE_ENV", sp_make_env);
      print_vector_list ("BUILD_TARGET", sp_build_target);
      print_single      ("OPTIMIZER_LEVEL", sp_opt_level);
      print_vector_list ("CFLAGS", sp_cflags);
      print_vector_list ("CXXFLAGS", sp_cxxflags);
      print_vector_list ("CPPFLAGS", sp_cppflags);
      print_vector_list ("LDFLAGS", sp_ldflags);

      print_group_list  ("Makefile Targets", sp_makefile_targets);

   end dump_specification;

end Port_Specification;
