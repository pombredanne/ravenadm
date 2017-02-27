with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Ada.Characters.Latin_1;

package body HelperText is

   package AS  renames Ada.Strings;
   package LAT renames Ada.Characters.Latin_1;

   --------------------------------------------------------------------------------------------
   --  int2str
   --------------------------------------------------------------------------------------------
   function int2str (A : Integer) return String
   is
      raw : constant String := A'Img;
      len : constant Natural := raw'Length;
   begin
      if A < 0 then
         return raw;
      else
         return raw (2 .. len);
      end if;
   end int2str;


   --------------------------------------------------------------------------------------------
   --  trim
   --------------------------------------------------------------------------------------------
   function trim (S : String) return String is
   begin
      return AS.Fixed.Trim (S, AS.Both);
   end trim;


   --------------------------------------------------------------------------------------------
   --  USS
   --------------------------------------------------------------------------------------------
   function USS (US : Text) return String is
   begin
         return SU.To_String (US);
   end USS;


   --------------------------------------------------------------------------------------------
   --  SUS
   --------------------------------------------------------------------------------------------
   function SUS (S : String) return Text is
   begin
      return SU.To_Unbounded_String (S);
   end SUS;


   --------------------------------------------------------------------------------------------
   --  equivalent #1
   --------------------------------------------------------------------------------------------
   function equivalent (A, B : Text) return Boolean
   is
      use type Text;
   begin
      return A = B;
   end equivalent;


   --------------------------------------------------------------------------------------------
   --  equivalent #2
   --------------------------------------------------------------------------------------------
   function equivalent (A : Text; B : String) return Boolean
   is
      A2S : constant String := USS (A);
   begin
      return A2S = B;
   end equivalent;


   --------------------------------------------------------------------------------------------
   --  hash
   --------------------------------------------------------------------------------------------
   function hash (key : Text) return CON.Hash_Type is
   begin
      return AS.Hash (USS (key));
   end hash;


   --------------------------------------------------------------------------------------------
   --  IsBlank #1
   --------------------------------------------------------------------------------------------
   function IsBlank (US : Text)   return Boolean is
   begin
      return SU.Length (US) = 0;
   end IsBlank;


   --------------------------------------------------------------------------------------------
   --  IsBlank #2
   --------------------------------------------------------------------------------------------
   function IsBlank (S  : String) return Boolean is
   begin
      return S'Length = 0;
   end IsBlank;


   --------------------
   --  contains  #1  --
   --------------------
   function contains (S : String; fragment : String) return Boolean is
   begin
      return (AS.Fixed.Index (Source => S, Pattern => fragment) > 0);
   end contains;


   --------------------
   --  contains  #2  --
   --------------------
   function contains (US : Text; fragment : String) return Boolean is
   begin
      return (SU.Index (Source => US, Pattern => fragment) > 0);
   end contains;


   --------------------------------------------------------------------------------------------
   --  initialize_markers
   --------------------------------------------------------------------------------------------
   procedure initialize_markers
     (block_text : in String;
      shuttle    : out Line_Markers) is
   begin
      shuttle.back_marker  := block_text'First;
      shuttle.front_marker := block_text'First;
   end initialize_markers;


   --------------------------------------------------------------------------------------------
   --  extract_line
   --------------------------------------------------------------------------------------------
   function extract_line
     (block_text : in String;
      shuttle    : in Line_Markers)
      return String is
   begin
      if shuttle.back_marker < block_text'First or else
        shuttle.front_marker < shuttle.back_marker or else
        shuttle.front_marker > block_text'Last
      then
         return "";
      end if;
      return block_text (shuttle.back_marker .. shuttle.front_marker);
   end extract_line;


   --------------------------------------------------------------------------------------------
   --  next_line_present
   --------------------------------------------------------------------------------------------
   function next_line_present
     (block_text : in String;
      shuttle    : in out Line_Markers)
      return Boolean is
   begin
      if shuttle.front_marker + 2 > block_text'Last then
         return False;
      end if;
      if shuttle.front_marker > block_text'First then
         shuttle.back_marker  := shuttle.front_marker + 2;
         shuttle.front_marker := shuttle.back_marker;
      end if;
      loop
         exit when shuttle.front_marker = block_text'Last;
         exit when block_text (shuttle.front_marker + 1) = ASCII.LF;
         shuttle.front_marker := shuttle.front_marker + 1;
      end loop;
      return True;
   end next_line_present;


   --------------------------------------------------------------------------------------------
   --  trailing_whitespace_present
   --------------------------------------------------------------------------------------------
   function trailing_whitespace_present (line : String) return Boolean
   is
      -- For now, whitespace is considered a hard tab and a space character
      last_char : constant Character := line (line'Last);
   begin
      case last_char is
         when LAT.Space | LAT.HT => return True;
         when others => return False;
      end case;
   end trailing_whitespace_present;


   --------------------------------------------------------------------------------------------
   --  trapped_space_character_present
   --------------------------------------------------------------------------------------------
   function trapped_space_character_present (line : String) return Boolean
   is
      back_marker : Natural := line'First;
   begin
      loop
         exit when back_marker + 1 >= line'Last;
         if line (back_marker) = LAT.Space and then
           line (back_marker + 1) = LAT.HT then
            return True;
         end if;
         back_marker := back_marker + 1;
      end loop;
      return False;
   end trapped_space_character_present;


end HelperText;
