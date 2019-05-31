-- Xlocate init.lua
-- Copyright Duane Robertson (duane@duanerobertson.com), 2017, 2019
-- Distributed under the LGPLv2.1 (https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html)

xlocate = {}
mod = xlocate
mod_name = 'xlocate'
mod.version = '2.0'


local xdata = minetest.get_mod_storage()


local function get_num_trans()
	local ntrans = xdata:get_int('number_translocators')
	if not (ntrans and tonumber(ntrans)) then
		print(mod_name..': Can\'t get number of translocators.')
		return 0
	end
	return ntrans
end


local function inc_num_trans()
	local ntrans = get_num_trans() + 1
	xdata:set_int('number_translocators', ntrans)
	return ntrans
end


local function get_item_data(meta)
	if not meta then
		print(mod_name..': Bad arguments to get_item_data')
		return
	end

	local id = meta:get_int('id')
	local owner = meta:get_string('owner')

	return id, owner
end


local function set_item_data(meta, id, owner)
	if not (meta and id and owner and type(id) == 'number' and type(owner) == 'string') then
		print(mod_name..': Bad arguments to set_item_data')
		return
	end

	meta:set_int('id', id)
	meta:set_string('owner', owner)
end


local function get_pair_data(id)
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


local function set_pair_data(id, pair)
	if not (id and pair and type(id) == 'number' and type(pair) == 'table') then
		print(mod_name..': Bad arguments to set_pair_data')
		return
	end

	local spair = minetest.serialize(pair)
	xdata:set_string('pair'..id, spair)
end


local function set_node_data(pos, id, owner, pair)
	local meta = minetest.get_meta(pos)
	if not meta then
		print(mod_name..': set_node_data can\'t get meta')
		return
	end

	set_item_data(meta, id, owner)

	if pair then
		set_pair_data(id, pair)
	end
end


local function get_node_data(pos, id, owner)
	local meta = minetest.get_meta(pos)
	if not meta then
		print(mod_name..': get_node_data can\'t get meta')
		return
	end

	local id, owner = get_item_data(meta)
	if not (id and owner) then
		print(mod_name..': get_node_data can\'t get id/owner')
		return
	end

	local pair = get_pair_data(id)

	return id, owner, pair
end


local function translocate(pos, node, clicker, itemstack, pointed_thing)
	if not (pos and clicker and xdata) then
		print(mod_name..': Bad arguments to translocate')
		return
	end

	local id, owner, pair = get_node_data(pos)
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
			if not node or node.name == mod_name..':translocator' then
				return
			end

			minetest.set_node(pos2, {name = mod_name..':translocator'})
			set_node_data(pos2, id, owner)

			print(mod_name..': recreated a missing translocator')
		end)
	end
end


local function trans_use(itemstack, user, pointed_thing)
	if not (itemstack and user) then
		print(mod_name..': Bad arguments to trans_use')
		return
	end

	local meta = itemstack:get_meta()
	local id, owner = get_item_data(meta)
	if not id then
		print(mod_name..': trans_use can\'t get id/owner')
		return
	end

	local player_name = user:get_player_name()
	minetest.chat_send_player(player_name, 'You see a serial number: ' .. id)
end


local function trans_place(itemstack, placer, pointed_thing)
	if not (itemstack and placer and pointed_thing and xdata) then
		print(mod_name..': Bad arguments to trans_place')
		return
	end

	local meta = itemstack:get_meta()
	local id, owner = get_item_data(meta)
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
	local pair = get_pair_data(id)
	if not pair or #pair > 1 then
		print(mod_name..': high error in translocator storage')
		return
	end

	local ret, place_good = minetest.item_place_node(itemstack, placer, pointed_thing)
	if place_good then
		pair[#pair+1] = pos
		set_node_data(pos, id, owner, pair)
	end

	return ret, place_good
end


local function trans_dig(pos, node, digger)
	if not (pos and node and digger and xdata) then
		print(mod_name..': Bad arguments to trans_dig')
		return
	end

	local player_name = digger:get_player_name()
	if minetest.is_protected(pos, player_name) then
		return
	end

	local id, owner, pair = get_node_data(pos)
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
	set_item_data(item:get_meta(), id, owner)
	if not inv:room_for_item('main', item) or not inv:add_item('main', item) then
		return
	end

	minetest.remove_node(pos)
	if #pair > 1 and minetest.serialize(pair[2]) == minetest.serialize(pos) then
		table.remove(pair, 2)
	else
		table.remove(pair, 1)
	end

	set_pair_data(id, pair)
end


local function trans_dest(pos)
	if not (pos and xdata) then
		print(mod_name..': Bad arguments to trans_dest')
		return
	end

	local id, owner, pair = get_node_data(pos)
	if not (id and owner and pair) then
		print(mod_name..': trans_dest can\'t get id/owner')
		return
	end

	minetest.after(1, function()
		-- Destruction was reflected in the database.
		local pair2 = get_pair_data(id)
		if #pair2 < #pair then
			return
		end

		minetest.set_node(pos, {name = mod_name..':translocator'})
		set_node_data(pos, id, owner)

		print(mod_name..': recreated a destroyed translocator')
	end)
end


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
	use_texture_alpha = true,
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
	light_source = 13,
	sounds = default.node_sound_glass_defaults(),
	selection_box = {
		type = 'fixed',
		fixed = {-0.25, -0.5, -0.25,  0.25, 0.5, 0.25}
	},
	on_rightclick = translocate,
	on_use = trans_use,
	on_place = trans_place,
	on_dig = trans_dig,
	on_destruct = trans_dest,
})

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

	local ntrans = inc_num_trans()
	local owner = player:get_player_name()
	local meta = itemstack:get_meta()
	set_item_data(meta, ntrans, owner)

	set_pair_data(ntrans, {})
end)
