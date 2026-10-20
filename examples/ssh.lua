local bibleit = require("bibleit")
-- The adapter owns host-key verification, authentication and connection lifetime.
-- execute_verified_ssh receives the wire command and optional cancellation context.
return function(execute_verified_ssh)
   local client = assert(bibleit.new_ssh_client(function(command, context)
      local stdout, err = execute_verified_ssh(command:string(), context)
      if not stdout then return nil, err end
      return bibleit.decode_command_response(command, stdout)
   end))
   return client
end
