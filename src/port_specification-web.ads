--  This file is covered by the Internet Software Consortium (ISC) License
--  Reference: ../License.txt

with Definitions; use Definitions;
with Ada.Text_IO;

package Port_Specification.Web is

   package TIO renames Ada.Text_IO;


   --  Convert specification to a static web page written to dossier
   procedure produce_page
     (specs   : Portspecs;
      variant : String;
      dossier : TIO.File_Type);

private

   --  standard page header used on all pages
   function page_header (title : String) return String;

   --  standard page footer used on all pages
   function page_footer return String;

   --  Escape certain characters that are quoted in html (&, <, >, ")
   function escape_value (raw : String) return String;

   --  formats to:
   --  <name>="<escaped value>"
   function nvpair (name, value : String) return String;

   --  return populated div enclosure
   function div (id, value : String) return String;

   --  returns the pre-populated web page template for the entire body
   function body_template return String;

   --  populate body template
   function generate_body (specs : Portspecs; variant : String) return String;

   --  html format WWW reference
   function format_homepage (homepage : String) return String;

   --  return "(dual)" or "(multi)" if appropriate
   function list_scheme (licenses, scheme : String) return String;

end Port_Specification.Web;
