fx_version 'cerulean'
game 'gta5'

shared_scripts {
	'@grids/shared/grids.lua',
	'sh_config.lua',
	'modules/**/sh_*.lua',
}

client_scripts {
	'@utils/client/misc.lua',
	'@utils/client/vehicles.lua',
	'cl_players.lua',
	'modules/**/cl_*.lua',
}

server_scripts {
	'@utils/server/players.lua',
	'sv_players.lua',
	'modules/**/sv_*.lua',
}