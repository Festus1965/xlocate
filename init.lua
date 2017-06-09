-- Xlocate init.lua
-- Copyright Duane Robertson (duane@duanerobertson.com), 2017
-- Distributed under the LGPLv2.1 (https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html)

xlocate = {}
xlocate.version = "1.0"
xlocate.path = minetest.get_modpath(minetest.get_current_modname())
xlocate.world = minetest.get_worldpath()


local inp = io.open(xlocate.world..'/xlocate_data.txt','r')
if inp then
	local d = inp:read('*a')
	xlocate.db = minetest.deserialize(d)
	inp:close()
end
if not xlocate.db then
	xlocate.db = {}
end
for _, i in pairs({'translocators'}) do
	if not xlocate.db[i] then
		xlocate.db[i] = {}
	end
end


-- Attempt to save data at shutdown (as well as periodically).
minetest.register_on_shutdown(function()
	local out = io.open(xlocate.world..'/xlocate_data.txt','w')	
	if out then
		print('Xlocate: Saving database at shutdown')
		out:write(minetest.serialize(xlocate.db))
		out:close()
	end
end)


local last_save_check = 0

minetest.register_globalstep(function(dtime)
	if not (dtime and type(dtime) == 'number') then
		return
	end

	local time = minetest.get_gametime()
	if not (time and type(time) == 'number') then
		return
	end

	if last_save_check and time - last_save_check < 30 then
		return
	end

	local out = io.open(xlocate.world..'/xlocate_data.txt','w')	
	if out then
		out:write(minetest.serialize(xlocate.db))
		out:close()
	end

  last_save_check = time
end)


local function translocate(pos, node, clicker, itemstack, pointed_thing)
	if not (pos and clicker and xlocate.db.translocators) then
		return
	end

	local meta = minetest.get_meta(pos)
	if not meta then
		return
	end

	local id = meta:get_string('id')
	local owner = meta:get_string('owner')
	if not (id and tonumber(id)) then
		return
	end

	local pair = xlocate.db.translocators[tonumber(id)]
	if not pair or #pair < 2 then
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
				return
			end

			-- If we can't get the node, we can't set it.
			local node = minetest.get_node_or_nil(pos2)
			if not node or node.name == 'xlocate:translocator' then
				return
			end

			minetest.set_node(pos2, {name = 'xlocate:translocator'})
			local meta = minetest.get_meta(pos2)
			if not meta then
				return
			end

			meta:set_string('id', id)
			meta:set_string('owner', owner)

			print('Xlocate: recreated a missing translocator')
		end)
	end
end

local function trans_use(itemstack, user, pointed_thing)
	if not (itemstack and user) then
		return
	end

	local data = minetest.deserialize(itemstack:get_metadata())
	if not (data and data.id) then
		return
	end

	local player_name = user:get_player_name()
	minetest.chat_send_player(player_name, "You see a serial number: "..data.id)
end

local function trans_place(itemstack, placer, pointed_thing)
	if not (itemstack and placer and pointed_thing and xlocate.db.translocators) then
		return
	end

	local data = minetest.deserialize(itemstack:get_metadata())
	if not (data and data.id and tonumber(data.id)) then
		return
	end

	local player_name = placer:get_player_name()
	if not data.owner or data.owner == '' then
		print('Xlocate: Unowned translocator has been assigned to placer.')
		data.owner = player_name
	end

	local pos = pointed_thing.above
	local pair = xlocate.db.translocators[tonumber(data.id)]
	if not pair or #pair > 1 then
		print('* Xlocate: high error in translocator storage')
		return
	end

	local ret, place_good = minetest.item_place_node(itemstack, placer, pointed_thing)
	if place_good then
		pair[#pair+1] = pos
		local meta = minetest.get_meta(pos)
		if not meta then
			return
		end

		meta:set_string('id', data.id)
		meta:set_string('owner', data.owner)
	end
	return ret, place_good
end

local function trans_dig(pos, node, digger)
	if not (pos and node and digger and xlocate.db.translocators) then
		return
	end

	local player_name = digger:get_player_name()
	if minetest.is_protected(pos, player_name) then
		return
	end

	local meta = minetest.get_meta(pos)
	if not meta then
		return
	end

	local id = meta:get_string('id')
	local owner = meta:get_string('owner')
	if owner == '' then
		owner = player_name
		print('Xlocate: Unowned translocator has been assigned to taker.')
	end
	local data = { id = id, owner = owner }
	if not (data and data.id and data.owner == player_name) then
		local privs = minetest.check_player_privs(player_name, {server=true})
		if privs then
			print('Xlocate: Admin has destroyed ['..data.owner..']\'s translocator')
			minetest.remove_node(pos)
		end
		return
	end

	local pair = xlocate.db.translocators[tonumber(data.id)]
	if not pair or #pair < 1 then
		print('* Xlocate: low error in translocator storage')
		minetest.remove_node(pos)
		return
	end

	local inv = digger:get_inventory()
	local item = ItemStack(node.name)
	local data_str = minetest.serialize(data)
	item:set_metadata(data_str)
	if not inv:room_for_item('main', item) or not inv:add_item('main', item) then
		return
	end

	minetest.remove_node(pos)
	if #pair > 1 and minetest.serialize(pair[2]) == minetest.serialize(pos) then
		table.remove(pair, 2)
	else
		table.remove(pair, 1)
	end
end

local function trans_dest(pos)
	if not (pos and xlocate.db.translocators) then
		return
	end

	local meta = minetest.get_meta(pos)
	if not meta then
		return
	end

	local id = meta:get_string('id')
	local owner = meta:get_string('owner')
	if not (id and owner) then
		return
	end

	if not xlocate.db.translocators[tonumber(id)] then
		return
	end
	local pair = table.copy(xlocate.db.translocators[tonumber(id)])

	minetest.after(1, function()
		if not xlocate.db.translocators[tonumber(id)] or #xlocate.db.translocators[tonumber(id)] < #pair then
			return
		end
		minetest.set_node(pos, {name = 'xlocate:translocator'})
		local meta = minetest.get_meta(pos)
		if not meta then
			return
		end

		meta:set_string('id', id)
		meta:set_string('owner', owner)

		print('Xlocate: recreated a destroyed translocator')
	end)
end

minetest.register_node("xlocate:translocator", {
	visual = 'mesh',
	mesh = "warps_translocator.obj",
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
	stack_max = 1,
	selection_box = {
		type = "fixed",
		fixed = {-0.25, -0.5, -0.25,  0.25, 0.5, 0.25}
	},
	on_rightclick = translocate,
	on_use = trans_use,
	on_place = trans_place,
	on_dig = trans_dig,
	on_destruct = trans_dest,
})

if minetest.get_modpath('inspire') then
  minetest.register_craft({
    output = 'xlocate:translocator 2',
    recipe = {
      {'', 'default:diamond', ''},
      {'default:mese_crystal', 'default:diamond', 'default:mese_crystal'},
      {'inspire:inspiration', 'default:diamond', 'inspire:inspiration'},
    }
  })
else
  minetest.register_craft({
    output = 'xlocate:translocator 2',
    recipe = {
      {'', 'default:diamond', ''},
      {'default:mese_crystal', 'default:diamond', 'default:mese_crystal'},
      {'default:mese', 'default:diamond', 'default:mese'},
    }
  })
end

minetest.register_on_craft(function(itemstack, player, old_craft_grid, craft_inv)
	if not (itemstack and player and xlocate.db.translocators and itemstack:get_name() == "xlocate:translocator") then
		return
	end

	local data = {}
	data.id = string.format('%d', #xlocate.db.translocators+1)
	data.owner = player:get_player_name()
	xlocate.db.translocators[#xlocate.db.translocators+1] = {}
	local data_str = minetest.serialize(data)
	itemstack:set_metadata(data_str)
end)
