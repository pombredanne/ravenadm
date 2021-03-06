--  This file is covered by the Internet Software Consortium (ISC) License
--  Reference: ../License.txt

package Signals is

   --  Returns True if Interrupt signal (control-C) has been detected
   function graceful_shutdown_requested return Boolean;

   --  Enable exception handlers to initiate a shutdown upon detecting an issue
   procedure initiate_shutdown;

private

   control_q_break : Boolean := False;

end Signals;
