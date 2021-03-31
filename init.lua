-- Xlocate init.lua
-- Copyright Duane Robertson (duane@duanerobertson.com), 2017, 2019
-- Distributed under the LGPLv2.1 (https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html)

xlocate = {}
local mod = xlocate
local mod_name = 'xlocate'
mod.version = '2.0'

mod.improv_teleport_selection = {}
mod.safe_nodes = {
	['default:snow'] = true,
}


do
	for k, v in pairs(minetest.registered_nodes) do
		if not v.walkable then
			mod.safe_nodes[k] = true
		elseif v.groups and v.groups.leaves then
			mod.safe_nodes[k] = true
		end
	end
end


local xdata = minetest.get_mod_storage()


minetest.register_craft({
	output = mod_name..':translocator 2',
	recipe = {
		{'', 'default:diamond', ''},
		{'default:mese_crystal', 'default:diamond', 'default:mese_crystal'},
		{'', 'default:diamond', ''},
	}
})


minetest.register_on_craft(function(itemstack, player, old_craft_grid, craft_inv)
	if not (itemstack and player and xdata and itemstack:get_name() == mod_name..':translocator') then
		return
	end

	local ntrans = mod.inc_num_trans()
	local owner = player:get_player_name()
	local meta = itemstack:get_meta()
	mod.set_item_data(meta, ntrans, owner)

	mod.set_pair_data(ntrans, {})
end)


minetest.register_craftitem(mod_name..':strange_super', {
	description = 'Strange Superposition',
	inventory_image = 'strange_super.png',
})


local coal = 'default:coal_lump'
if minetest.get_modpath('fun_tools') then
	coal = 'group:coal'
end


minetest.register_craft({
	output = mod_name..':strange_super',
	recipe = {
		{'group:stone', 'group:stone', 'group:stone'},
		{'group:stone', 'group:stone', 'group:stone'},
		{'group:stone', coal, 'group:stone'},
	}
})


minetest.register_craft({
	output = mod_name..':strange_super',
	recipe = {
		{'default:ice', 'default:ice', 'default:ice'},
		{'default:ice', 'default:ice', 'default:ice'},
		{'default:ice', coal, 'default:ice'},
	}
})


minetest.register_craft({
	output = mod_name..':improv_teleport',
	recipe = {
		{ mod_name..':strange_super', mod_name..':strange_super', mod_name..':strange_super'},
		{ mod_name..':strange_super', mod_name..':strange_super', mod_name..':strange_super'},
		{ mod_name..':strange_super', '', mod_name..':strange_super'},
	}
})


function mod.get_item_data(meta)
	if not meta then
		print(mod_name..': Bad arguments to get_item_data')
		return
	end

	local id = meta:get_int('id')
	local owner = meta:get_string('owner')

	return id, owner
end


function mod.get_node_data(pos, id, owner)
	local meta = minetest.get_meta(pos)
	if not meta then
		print(mod_name..': get_node_data can\'t get meta')
		return
	end

	local id, owner = mod.get_item_data(meta)
	if not (id and owner) then
		print(mod_name..': get_node_data can\'t get id/owner')
		return
	end

	local pair = mod.get_pair_data(id)

	return id, owner, pair
end


function mod.get_pair_data(id)
	if not (id and tonumber(id)) then
		print(mod_name..': Bad arguments to get_pair_data')
		return
	end

	local spair = xdata:get_string('pair'..tonumber(id))
	if not spair then
		print(mod_name..': get_pair_data can\'t get spair')
		return
	end
	local pair = minetest.deserialize(spair)
	if type(pair) == 'table' then
		return pair
	end
end


function mod.get_num_trans()
	local ntrans = xdata:get_int('number_translocators')
	if not (ntrans and tonumber(ntrans)) then
		print(mod_name..': Can\'t get number of translocators.')
		return 0
	end
	return ntrans
end


function mod.improv_teleport_menu(itemstack, user, pointed_thing)
	local player_name = user:get_player_name()
	if not player_name then
		return
	end

	mod.improv_teleport_selection[player_name] = nil

	if not mod.improv_teleport_locations then
		local locations = { ['far_away'] = true, }

		if minetest.get_modpath('mapgen') then
			for _, map in pairs(mapgen.registered_realms) do
				if not map.no_random_teleport then
					local name = map.name or map.mapgen
					locations[name] = true
				end
			end
		end

		local list_loc = {}
		for k, v in pairs(locations) do
			table.insert(list_loc, k)
		end

		table.sort(list_loc)
		mod.improv_teleport_locations = list_loc
	end

	local list_loc = {}
	for k, v in pairs(mod.improv_teleport_locations) do
		local s = v:gsub('^tg_', '')
		s = s:gsub('_', ' ')
		s = s:gsub('%f[%a]%a', string.upper)
		list_loc[k] = s
	end

	local fs = 'size[4,4]'
	fs = fs .. 'textlist[0,0;4,3.5;xlocate_tp_areas;'
	for k, v in pairs(list_loc) do
		fs = fs .. v .. ','
	end
	fs = fs:gsub(',$', ']')
	fs = fs .. 'button_exit[0,3.5;2,1;xlocate_do_it;Teleport]'
	fs = fs .. 'button_exit[2,3.5;2,1;xlocate_cancel;OMG No!]'

	minetest.show_formspec(player_name, 'improv_teleport_menu', fs)
end


function mod.improv_teleport_to(player, location)
	if not (player and location) then
		return
	end

	player:set_wielded_item(nil)

	local player_pos = player:get_pos()
	local pos
	if location == 'far_away' then
		pos = vector.new(
			math.random(60000) - 30000,
			player_pos.y,
			math.random(60000) - 30000
		)
	elseif minetest.get_modpath('mapgen') then
		local maps = {}
		for _, map in pairs(mapgen.registered_realms) do
			if map.name == location or map.mapgen == location then
				if not map.no_random_teleport then
					table.insert(maps, map)
				end
			end
		end

		if #maps < 1 then
			return
		end

		local map = maps[math.random(#maps)]

		local map_min = table.copy(map.realm_minp)
		local map_max = table.copy(map.realm_maxp)

		player_pos.x = math.min(map_max.x, math.max(map_min.x, player_pos.x))
		player_pos.z = math.min(map_max.z, math.max(map_min.z, player_pos.z))

		pos = vector.new(
			math.random(1000) + player_pos.x - 500,
			-31000,
			math.random(1000) + player_pos.z - 500
		)

		pos.x = math.min(map_max.x, math.max(map_min.x, pos.x))
		pos.z = math.min(map_max.z, math.max(map_min.z, pos.z))

		if map.mapgen and mapgen.registered_spawns[map.mapgen] then
			for i = 1, 4000 do
				pos.y = mapgen.registered_spawns[map.mapgen](map, pos.x, pos.z, true)
				--print(dump(pos.y))
				if pos.y and pos.y <= map_max.y and pos.y >= map_min.y
				and pos.y > map.sealevel then
					break
				end

				pos.x = math.random(1000) + player_pos.x - 500
				pos.z = math.random(1000) + player_pos.z - 500
				pos.x = math.min(map_max.x, math.max(map_min.x, pos.x))
				pos.z = math.min(map_max.z, math.max(map_min.z, pos.z))
			end
		end

		if not pos.y or pos.y > map_max.y or pos.y < map_min.y then
			if map.water_level and type(map.water_level) == 'number'
			and map.water_level > map_min.y and map.water_level < map_max.y then
				pos.y = map.water_level + 20
			else
				local c = math.random(map.realm_minp.y, map.realm_maxp.y)
				--print(c, pos.y)
				pos.y = c
			end
		end
	end

	if pos and pos.y then
		pos.y = pos.y + 2
		player:setpos(pos)
		minetest.after(5, function()
			local n = minetest.get_node_or_nil(pos)
			if minetest.get_modpath('tnt') and n
			and n.name and not mod.safe_nodes[n.name] then
				print(mod_name..': Teleportation accident: ' .. n.name)
				local upos = table.copy(pos)
				upos.y = upos.y - 1
				minetest.remove_node(pos)
				minetest.remove_node(upos)
				tnt.boom(pos, { radius = 5 })
			end
		end)
	end
end


function mod.inc_num_trans()
	local ntrans = mod.get_num_trans() + 1
	xdata:set_int('number_translocators', ntrans)
	return ntrans
end


function mod.set_item_data(meta, id, owner)
	if not (meta and id and owner and type(id) == 'number' and type(owner) == 'string') then
		print(mod_name..': Bad arguments to set_item_data')
		return
	end

	meta:set_int('id', id)
	meta:set_string('owner', owner)
end


function mod.set_node_data(pos, id, owner, pair)
	local meta = minetest.get_meta(pos)
	if not meta then
		print(mod_name..': set_node_data can\'t get meta')
		return
	end

	mod.set_item_data(meta, id, owner)

	if pair then
		mod.set_pair_data(id, pair)
	end
end


function mod.set_pair_data(id, pair)
	if not (id and pair and type(id) == 'number' and type(pair) == 'table') then
		print(mod_name..': Bad arguments to set_pair_data')
		return
	end

	local spair = minetest.serialize(pair)
	xdata:set_string('pair'..id, spair)
end


function mod.trans_dest(pos)
	if not (pos and xdata) then
		print(mod_name..': Bad arguments to trans_dest')
		return
	end

	local id, owner, pair = mod.get_node_data(pos)
	if not (id and owner and pair) then
		print(mod_name..': trans_dest can\'t get id/owner')
		return
	end

	minetest.after(1, function()
		-- Destruction was reflected in the database.
		local pair2 = mod.get_pair_data(id)
		if #pair2 < #pair then
			return
		end

		minetest.set_node(pos, {name = mod_name..':translocator'})
		mod.set_node_data(pos, id, owner)

		print(mod_name..': recreated a destroyed translocator')
	end)
end


function mod.trans_dig(pos, node, digger)
	if not (pos and node and digger and xdata) then
		print(mod_name..': Bad arguments to trans_dig')
		return
	end

	local player_name = digger:get_player_name()
	if minetest.is_protected(pos, player_name) then
		return
	end

	local id, owner, pair = mod.get_node_data(pos)
	if not (id and owner) then
		print(mod_name..': trans_dig can\'t get id/owner')
		return
	end
	if owner == '' then
		owner = player_name
		print(mod_name..': Unowned translocator has been assigned to taker.')
	end

	if owner ~= player_name then
		local privs = minetest.check_player_privs(player_name, {server=true})
		if privs then
			print(mod_name..': Admin has destroyed ['..owner..']\'s translocator')
			minetest.remove_node(pos)
		end
		return
	end

	if not pair or #pair < 1 then
		print('* Xlocate: low error in translocator storage')
		minetest.remove_node(pos)
		return
	end

	local inv = digger:get_inventory()
	local item = ItemStack(node.name)
	mod.set_item_data(item:get_meta(), id, owner)
	if not inv:room_for_item('main', item) or not inv:add_item('main', item) then
		return
	end

	minetest.remove_node(pos)
	if #pair > 1 and minetest.serialize(pair[2]) == minetest.serialize(pos) then
		table.remove(pair, 2)
	else
		table.remove(pair, 1)
	end

	mod.set_pair_data(id, pair)
end


function mod.trans_place(itemstack, placer, pointed_thing)
	if not (itemstack and placer and pointed_thing and xdata) then
		print(mod_name..': Bad arguments to trans_place')
		return
	end

	local meta = itemstack:get_meta()
	local id, owner = mod.get_item_data(meta)
	if not id then
		print(mod_name..': trans_place can\'t get id/owner')
		return
	end

	local player_name = placer:get_player_name()
	if not owner or owner == '' then
		print(mod_name..': Unowned translocator has been assigned to placer.')
		owner = player_name
	end

	local pos = pointed_thing.above
	local pair = mod.get_pair_data(id)
	if not pair or #pair > 1 then
		print(mod_name..': high error in translocator storage')
		return
	end

	local ret, place_good = minetest.item_place_node(itemstack, placer, pointed_thing)
	if place_good then
		pair[#pair+1] = pos
		mod.set_node_data(pos, id, owner, pair)
	end

	return ret, place_good
end


function mod.trans_use(itemstack, user, pointed_thing)
	if not (itemstack and user) then
		print(mod_name..': Bad arguments to trans_use')
		return
	end

	local meta = itemstack:get_meta()
	local id, owner = mod.get_item_data(meta)
	if not id then
		print(mod_name..': trans_use can\'t get id/owner')
		return
	end

	local player_name = user:get_player_name()
	minetest.chat_send_player(player_name, 'You see a serial number: ' .. id)
end


function mod.translocate(pos, node, clicker, itemstack, pointed_thing)
	if not (pos and clicker and xdata) then
		print(mod_name..': Bad arguments to translocate')
		return
	end

	local id, owner, pair = mod.get_node_data(pos)
	if not pair or #pair < 2 then
		print(mod_name..': translocate can\'t get id/owner')
		return
	end

	local pos2
	if minetest.serialize(pair[2]) == minetest.serialize(pos) then
		pos2 = pair[1]
	else
		pos2 = pair[2]
	end

	if pos2 then
		clicker:setpos(pos2)

		-- If the mated translocator doesn't exist, recreate it.
		minetest.after(1, function()
			if not owner then
				print(mod_name..': translocate can\'t get id/owner')
				return
			end

			-- If we can't get the node, we can't set it.
			local node = minetest.get_node_or_nil(pos2)
			if node and node.name == mod_name..':translocator' then
				return
			end

			minetest.set_node(pos2, {name = mod_name..':translocator'})
			mod.set_node_data(pos2, id, owner)

			print(mod_name..': recreated a missing translocator')
		end)
	end
end


minetest.register_on_player_receive_fields(function(player, formname, fields)
	if not (player and fields and formname == 'improv_teleport_menu') then
		return
	end

	local player_name = player:get_player_name()
	if not player_name then
		return
	end

	if fields['xlocate_do_it'] == 'Teleport' then
		local i = mod.improv_teleport_selection[player_name]
		if mod.improv_teleport_selection[player_name]
		and i and mod.improv_teleport_locations[i] then
			local tp = mod.improv_teleport_locations[i]
			mod.improv_teleport_to(player, tp)
		end
	elseif fields['xlocate_tp_areas'] then
		local t = minetest.explode_textlist_event(fields['xlocate_tp_areas'])
		mod.improv_teleport_selection[player_name] = t.index
	else
		return
	end
end)


minetest.register_node(mod_name..':translocator', {
	visual = 'mesh',
	mesh = 'warps_translocator.obj',
	description = 'Translocator',
	tiles = {'warps_translocator.png'},
	drawtype = 'mesh',
	sunlight_propagates = true,
	walkable = false,
	paramtype = 'light',
	paramtype2 = 'facedir',
	use_texture_alpha = 'blend',
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
	light_source = 13,
	sounds = default.node_sound_glass_defaults(),
	selection_box = {
		type = 'fixed',
		fixed = {-0.25, -0.5, -0.25,  0.25, 0.5, 0.25}
	},
	on_rightclick = mod.translocate,
	on_use = mod.trans_use,
	on_place = mod.trans_place,
	on_dig = mod.trans_dig,
	on_destruct = mod.trans_dest,
})


minetest.register_craftitem(mod_name..':improv_teleport', {
	description = 'Improvised Teleporter',
	inventory_image = 'improv_teleport.png',
	stack_max = 1,
	on_use = mod.improv_teleport_menu,
})
