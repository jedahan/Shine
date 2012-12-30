--[[
	Shine's logging system.
]]

if Shine.Error then return end

Script.Load "lua/Utility.lua"

local EntityListToTable = EntityListToTable
local GetEntsByClass = Shared.GetEntitiesWithClassname

local Time = Shared.GetSystemTime
local Floor = math.floor
local StringFormat = string.format

local MonthData = {
	{ Name = "January", Length = 31 },
	{ Name = "February", Length = 28, LeapLength = 29 },
	{ Name = "March", Length = 31 },
	{ Name = "April", Length = 30 },
	{ Name = "May", Length = 31 },
	{ Name = "June", Length = 30 },
	{ Name = "July", Length = 31 },
	{ Name = "August", Length = 31 },
	{ Name = "September", Length = 30 },
	{ Name = "October", Length = 31 },
	{ Name = "November", Length = 30 },
	{ Name = "December", Length = 31 }
}

local function GetDate( Logging )
	local SysTime = Time()

	local Year = Floor( SysTime / 31557600 )
	local LeapYear = ( ( Year + 2 ) % 4 ) == 0

	local NumOfExtraDays = Floor( ( Year - 2 ) / 4 )

	local Days = Floor( ( SysTime / 86400 ) - ( Year * 365 ) - NumOfExtraDays )

	Year = Year + 1970

	local Day = 0
	local Month = 0
	local Sum = 0
	for i = 1, #MonthData do
		local CurMonth = MonthData[ i ]
		local Length = LeapYear and ( CurMonth.LeapLength or CurMonth.Length ) or CurMonth.Length

		Sum = Sum + Length

		if Days <= Sum then
			Day = Days - Sum + Length + ( LeapYear and 1 or 0 )
			Month = i
			break
		end
	end

	local DateFormat = Shine.Config.DateFormat
	local Parsed = string.Explode( DateFormat, "-" )

	local FormatString = Logging and 
		"[%0"..#Parsed[ 1 ].."i:%0"..#Parsed[ 2 ].."i:%0"..#Parsed[ 3 ].."i]" 
		or "%0"..#Parsed[ 1 ].."i_%0"..#Parsed[ 2 ].."i_%0"..#Parsed[ 3 ].."i"

	local Elements = {}
	for i = 1, 3 do
		Elements[ i ] = ( Parsed[ i ]:find( "d" ) and Day ) or ( Parsed[ i ]:find( "m" ) and Month ) or ( Parsed[ i ]:find( "y" ) and tostring( Year ):sub( 5 - #Parsed[ i ], 4 ) )
	end

	return StringFormat( FormatString, Elements[ 1 ], Elements[ 2 ], Elements[ 3 ] )
end
Shine.GetDate = GetDate

local function GetTimeString()
	local SysTime = Time()
	local Seconds = Floor( SysTime % 60 )
	local Minutes = Floor( ( SysTime / 60 ) % 60 )
	local Hours = Floor( ( ( SysTime / 60 ) / 60 ) % 24 )
	
	return StringFormat( "[%02i:%02i:%02i]", Hours, Minutes, Seconds )
end
Shine.GetTimeString = GetTimeString

Shared.OldMessage = Shared.OldMessage or Shared.Message

function Shared.Message( String )
	return Shared.OldMessage( GetDate( true )..GetTimeString()..String )
end

local function GetCurrentLogFile()
	return Shine.Config.LogDir..GetDate()..".txt"--Some way to get the date?
end

function Shine.LogString( String, Echo )
	local OldLog, Err = io.open( GetCurrentLogFile(), "r" )

	local Data = ""

	if OldLog then
		Data = OldLog:read( "*all" )
		OldLog:close()
	end
	
	local LogFile, Err = io.open( GetCurrentLogFile(), "w+" )

	if not LogFile then
		Shared.Message( StringFormat( "Error writing to log file: %s", Err  ) )

		return
	end

	LogFile:write( Data, GetTimeString(), String, "\n" )

	if Echo then
		Shared.Message( String )
	end

	LogFile:close()
end

function Shine:Print( String, Format, ... )
	String = Format and StringFormat( String, ... ) or String

	Shared.Message( String )

	self.LogString( String )
end

function Shine:Notify( Player, String, Format, ... )
	local Message = Format and StringFormat( String, ... ) or String

	Message = Message:sub( 1, kMaxChatLength )

	if type( Player ) == "table" then
		for i = 1, #Player do
			Server.SendNetworkMessage( Player[ i ], "Chat", BuildChatMessage( false, "", -1, kTeamReadyRoom, kNeutralTeamType, Message ), true )
		end
	elseif Player then
		Server.SendNetworkMessage( Player, "Chat", BuildChatMessage( false, "", -1, kTeamReadyRoom, kNeutralTeamType, Message ), true )
	else
		local Players = EntityListToTable( GetEntsByClass( "Player" ) )

		for i = 1, #Players do
			Server.SendNetworkMessage( Players[ i ], "Chat", BuildChatMessage( false, "", -1, kTeamReadyRoom, kNeutralTeamType, Message ), true )
		end
	end

	self:Print( "Shine Notify: %s", true, Message )
end

function Shine:AdminPrint( Client, String, Format, ... )
	Shine:Print( String, Format, ... )
	
	if not Client then return end

	return ServerAdminPrint( Client, Format and StringFormat( String, ... ) or String )
end