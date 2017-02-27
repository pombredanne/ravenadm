package File_Operations is

   file_handling    : exception;

      --  Generic function to scan a text file and convert to a string
   function get_file_contents (dossier : String) return String;

   --  Generic procedure to convert a string to a new text file
   --  exception thrown on failures
   procedure dump_contents_to_file
     (contents : String;
      dossier  : String);

end File_Operations;
