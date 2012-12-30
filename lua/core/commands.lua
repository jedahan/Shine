--[[
	Shine console/chat command handling.
]]

local Round = math.Round

local StringConcatArgs = StringConcatArgs
local StringExplode = string.Explode

local TableConcat = table.concat
local TableRemove = table.remove

--[[
	Command object.
	Stores the console command, chat command and the function to run when these commands are used.
	Last argument specifies whether to hide the chat message of the player that used it.
]]
local CommandMeta = {}
CommandMeta.__index = CommandMeta

--[[
	Adds a parameter to a command. This defines what an argument should be parsed into.
	For instance, a paramter of type "client" will be parsed into a client from their name.
]]
function CommandMeta:AddParam( Table )
	assert( type( Table ) == "table", "Bad argument #1 to AddParam, table expected, got "..type( Table ) )

	local Args = self.Arguments
	Args[ #Args + 1 ] = Table
end

function CommandMeta:Help( HelpString )
	assert( type( HelpString ) == "string", "Bad argument #1 to Help, string expected, got "..type( HelpString ) )

	self.Help = HelpString
end

--[[
	Creates a command object. The object stores the console command, chat command, function to run, permission setting and silent setting.
	It can also have parameters added to it to pass to its function.
]]
local function Command( ConCommand, ChatCommand, Function, NoPermissions, Silent )
	return setmetatable( {
		ConCmd = ConCommand,
		ChatCmd = ChatCommand,
		Func = Function,
		NoPerm = NoPermissions,
		Silent = Silent,
		Arguments = {}
	}, CommandMeta )
end

Shine.Commands = {}
Shine.ChatCommands = {}

local HookedCommands = {}

--[[
	Registers a Shine command.
	Inputs: Console command to assign, optional chat command to assign, function to run, optional silent flag to always be silent.
]]
function Shine:RegisterCommand( ConCommand, ChatCommand, Function, NoPerm, Silent )
	assert( type( ConCommand ) == "string", "Bad argument #1 to RegisterCommand, string expected, got "..type( ConCommand ) )
	if ChatCommand then
		assert( type( ChatCommand ) == "string" or type( ChatCommand ) == "table", "Bad argument #2 to RegisterCommand, string or table expected, got "..type( ChatCommand ) )
	end
	assert( type( Function ) == "function", "Bad argument #3 to RegisterCommand, function expected, got "..type( Function ) )

	local Commands = self.Commands

	local CmdObj = Command( ConCommand, ChatCommand, Function, NoPerm, Silent )

	Commands[ ConCommand ] = CmdObj
	
	if ChatCommand then
		local ChatCommands = self.ChatCommands
		if type( ChatCommand ) == "table" then
			for i = 1, #ChatCommand do
				ChatCommands[ ChatCommand[ i ] ] = CmdObj
			end
		else
			ChatCommands[ ChatCommand ] = CmdObj
		end
	end

	if not HookedCommands[ ConCommand ] then --This prevents hooking again if a plugin is reloaded, which causes doubles or more of the command.
		Event.Hook( "Console_"..ConCommand, function( Client, ... )
			return Shine:RunCommand( Client, ConCommand, ... )
		end )
		HookedCommands[ ConCommand ] = true
	end

	return CmdObj
end

--[[
	Removes a registered Shine command.
	Inputs: Console command, optional chat command.
]]
function Shine:RemoveCommand( ConCommand, ChatCommand )
	self.Commands[ ConCommand ] = nil
	if ChatCommand then
		if type( ChatCommand ) == "table" then
			for i = 1, #ChatCommand do
				self.ChatCommands[ ChatCommand[ i ] ] = nil
			end
		else
			self.ChatCommands[ ChatCommand ] = nil
		end
	end
end

--More generic clamp for use with the number argument type.
local function MathClamp( Number, Min, Max )
    if not Number then return nil end
    if not Max then
        return Number > Min and Number or Min
    elseif not Min then
        return Number < Max and Number or Max
    elseif not Max and not Min then
        return Number
    else
        if Number < Min then return Min end
        if Number > Max then return Max end
        return Number
    end
end

local function isfunction( Func )
	return type( Func ) == "function"
end

local ParamTypes = {
	string = function( Client, String, Table )
		if not String then return  isfunction( Table.Default ) and Table.Default() or Table.Default end

		return Table.MaxLength and String:sub( 1, Table.MaxLength ) or String
	end,
	client = function( Client, String, Table )
		if not String then return  isfunction( Table.Default ) and Table.Default() or Table.Default end

		if String == "^" then return Client end
		return Shine:GetClient( String )
	end,
	clients = function( Client, String, Table )
		if not String then return isfunction( Table.Default ) and Table.Default() or Table.Default end

		if String == "*" then
			return Shine.GetAllClients()
		end

		if String == "@spectate" then
			return Shine.GetTeamClients( kTeamReadyRoom )
		end

		if String == "@marine" then
			return Shine.GetTeamClients( 1 )
		end

		if String == "@alien" then
			return Shine.GetTeamClients( 2 )
		end

		local Vals = StringExplode( String, "," )
		
		local Clients = {}
		
		for i = 1, #Vals do
			local Val = Vals[ i ]
			local CurClient 
			if Val == "^" then
				CurClient = Client
			else
				CurClient = Shine:GetClient( Val )
			end
			if CurClient then
				Clients[ #Clients + 1 ] = CurClient
			end
		end
		
		return Clients
	end,
	number = function( Client, String, Table )
		local Num = MathClamp( tonumber( String ), Table.Min, Table.Max )

		if not Num then
			return isfunction( Table.Default ) and Table.Default() or Table.Default
		end

		return Table.Round and Round( Num ) or Num
	end,
	boolean = function( Client, String, Table )
		if not String then return isfunction( Table.Default ) and Table.Default() or Table.Default end

		local ToNum = tonumber( String )

		return ToNum and ToNum ~= 0 or String ~= "false"
	end,
	team = function( Client, String, Table )
		if not String then return isfunction( Table.Default ) and Table.Default() or Table.Default end

		local ToNum = tonumber( String )

		if ToNum then return MathClamp( Round( ToNum ), 1, 2 ) end

		if String:lower():find( "marine" ) then return 1 end
		
		if String:lower():find( "alien" ) then return 2 end

		return nil
	end 
}

local function ParseParameter( Client, String, Table )
    local Type = Table.Type
    if String then
        return ParamTypes[ Type ] and ParamTypes[ Type ]( Client, String, Table )
    else
        if not Table.Optional then return nil end
        return ParamTypes[ Type ] and ParamTypes[ Type ]( Client, String, Table )
    end
end

function Shine:RunCommand( Client, ConCommand, ... )
	local Command = self.Commands[ ConCommand ]

	if not Command then return end

	if not self:GetPermission( Client, ConCommand ) then 
		self:Notify( Client:GetControllingPlayer(), "You do not have permission to use %s.", true, ConCommand )
		return 
	end

	local Args = { ... }

	local ParsedArgs = {}
	local ExpectedArgs = Command.Arguments
	local ExpectedCount = #ExpectedArgs

	for i = 1, ExpectedCount do
		local CurArg = ExpectedArgs[ i ]

		--Convert the string argument into the requested type.
		ParsedArgs[ i ] = ParseParameter( Client, Args[ i ], CurArg )

		--Specifically check for nil (boolean argument could be false).
		if ParsedArgs[ i ] == nil and not CurArg.Optional then
			if CurArg.Type:find( "client" ) then --No client means no match.
				self:Notify( Client:GetControllingPlayer(), "No matching %s found.", true, CurArg.Type == "client" and "player was" or "players were" )
			else
				self:Notify( Client:GetControllingPlayer(), CurArg.Error or "Incorrect argument #%s to %s.", true, i, ConCommand )
			end

			return
		end

		--Take rest of line should grab the entire rest of the argument list.
		if CurArg.Type == "string" and CurArg.TakeRestOfLine then
			if i == ExpectedCount then
				local Rest = TableConcat( Args, " ", i + 1 )
				if Rest ~= "" then
					ParsedArgs[ i ] = ParsedArgs[ i ].." "..Rest
				end
				if CurArg.MaxLength then
					ParsedArgs[ i ] = ParsedArgs[ i ]:sub( 1, CurArg.MaxLength )
				end
			else
				self:Print( "Take rest of line called on function expecting more arguments!" )
				self:Notify( Client:GetControllingPlayer(), "The author of this command misconfigured it. If you know them, tell them!" )
				return
			end
		end

		--Ensure the calling client can target the return client.
		if CurArg.Type == "client" and not CurArg.IgnoreCanTarget then
			if not self:CanTarget( Client, ParsedArgs[ i ] ) then
				self:Notify( Client:GetControllingPlayer(), CurArg.Error or "You do not have permission to target %s.", true, ParsedArgs[ i ]:GetControllingPlayer():GetName() )
				return
			end
		end

		--Ensure the calling client can target every returned client.
		if CurArg.Type == "clients" and not CurArg.IgnoreCanTarget then
			local ParsedArg = ParsedArgs[ i ]
			if ParsedArg then
				for j = 1, #ParsedArg do
					if not self:CanTarget( Client, ParsedArg[ j ] ) then
						TableRemove( ParsedArg, j )
					end
				end

				if #ParsedArg == 0 then
					self:Notify( Client:GetControllingPlayer(), CurArg.Error or "You do not have permission to target anyone you specified." )
					return
				end
			end
		end
	end

	--Log the command's execution.
	self:Print( "%s[%s] ran command %s with arguments: %s", true, Client and Client:GetControllingPlayer():GetName() or "Console", Client and Client:GetUserId() or "N/A", ConCommand, TableConcat( Args, ", " ) )

	--Run the command with the parsed arguments we've gathered.
	Command.Func( Client, unpack( ParsedArgs ) )
end

--Hook into the chat, execute commands if they match up.
Shine.Hook.Add( "PlayerSay", "CommandExecute", function( Client, Message )
	local Exploded = StringExplode( Message.message, " " )

	local Directive

	if Exploded[ 1 ]:sub( 1, 1 ):find( "[^%w]" ) then --They've done !, / or some other special character first.
		Directive = Exploded[ 1 ]:sub( 1, 1 )
		Exploded[ 1 ] = Exploded[ 1 ]:sub( 2, #Exploded[ 1 ] )
	end

	if not Directive then return end --Avoid accidental invocation.

	local CommandObj = Shine.ChatCommands[ Exploded[ 1 ] ]
	if not CommandObj then return end --Command does not exist.

	TableRemove( Exploded, 1 ) --Get rid of the first argument, it's just the chat command.

	local ConCommand = CommandObj.ConCmd --Get the associated console command.

	Shine:RunCommand( Client, ConCommand, unpack( Exploded ) ) --Run the command.

	if CommandObj.Silent then return "" end --If the command specifies it is silent, override their message with blank.
	if Shine.Config.SilentChatCommands then return "" end --If the global silent chat commands setting is on, silence the message.
	if Directive and Directive == "/" then return "" end --If they used / to invoke the command, silence it. (SourceMod style)
end )