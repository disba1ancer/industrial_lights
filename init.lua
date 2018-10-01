local function copytable(t)
	local key, value, tt
	tt = {}
	for key, value in pairs(t) do
		tt[key] = value
	end
	return tt
end

function stringize_table(t)
	local str = ""
	if type(t) ~= "table" then
		str = str .. tostring(t)
	else
		str = str .. "{\n"
		local key, value
		for key, value in pairs(t) do
			str = str .. key .. ": " .. stringize_table(value) .. ", "
		end
		str = str .. "\n}"
	end
	return str
end

local directions = {
	{x = 0, y = 0, z =-1},
	{x = 0, y = 0, z = 1},
	{x = 0, y =-1, z = 0},
	{x = 0, y = 1, z = 0},
	{x =-1, y = 0, z = 0},
	{x = 1, y = 0, z = 0},
}

local blocks_with_lights = {}

local function wrap_vmanip(vmanip)
	local vmanip_func_list = {
		"read_from_map",
		"write_to_map",
		"get_node_at",
		"set_node_at",
		"get_data",
		"set_data",
		"update_map",
		"set_lighting",
		"get_light_data",
		"set_light_data",
		"get_param2_data",
		"set_param2_data",
		"calc_lighting",
		"update_liquids",
		"get_emerged_area"
	}
	local wrapped_vmanip = {__vmanip = vmanip}
	for _, func_name in ipairs(vmanip_func_list) do
		wrapped_vmanip[func_name] = function(self, ...)
			return self.__vmanip[func_name](self.__vmanip, ...)
		end
	end
	return wrapped_vmanip
end

local core_voxelmanip = VoxelManip

VoxelManip = function(p1, p2)
	local vmanip = wrap_vmanip(core_voxelmanip(p1, p2))
	local write_to_map = vmanip.write_to_map
	vmanip.write_to_map = function(self, ...)
		return write_to_map(self, ...)
	end
	return vmanip
end
minetest.get_voxel_manip = VoxelManip

local function scanAndWriteSpace(pos, direction, lightpower, callback)
	local lightpos = vector.add(pos, direction)
	local areabeg, areaend = copytable(lightpos), copytable(lightpos)
	--local uptime = minetest.get_server_uptime()
	while minetest.registered_nodes[minetest.get_node(lightpos).name].paramtype == "light" and lightpower > 0 do
		local blockpos = vector.devide(lightpos, 16)
		if type(callback) == "function" then
			callback()
		end
		--blocks_with_lights[minetest.hash_node_position(blockpos)][pos] = uptime
		lightpos = vector.add(lightpos, direction)
		lightpower = lightpower - 1
		local function extendArea(abegin, aend, direction)
			if direction.x < 0 then
				abegin.x = abegin.x + direction.x
			else
				aend.x = aend.x + direction.x
			end
			if direction.y < 0 then
				abegin.y = abegin.y + direction.y
			else
				aend.y = aend.y + direction.y
			end
			if direction.z < 0 then
				abegin.z = abegin.z + direction.z
			else
				aend.z = aend.z + direction.z
			end
		end
		extendArea(areabeg, areaend, direction)
	end
end

local function construct_light_via_mapgen(step, begpos, raylength)
	local lightlevel = 14
	local endpos = vector.add(begpos, vector.multiply(step, raylength - 1))
	local minpos, maxpos = {
		x = math.min(begpos.x, endpos.x),
		y = math.min(begpos.y, endpos.y),
		z = math.min(begpos.z, endpos.z)
	}, {
		x = math.max(begpos.x, endpos.x),
		y = math.max(begpos.y, endpos.y),
		z = math.max(begpos.z, endpos.z)
	}
	local vmanip = VoxelManip()
	local e1, e2 = vmanip:read_from_map(minpos, maxpos)
	local varea = VoxelArea:new{MinEdge = e1, MaxEdge = e2}
	local light_data = vmanip:get_light_data()
	for i in varea:iterp(minpos, maxpos) do
		if light_data[i] then
			local sunlight = light_data[i] % 16 -- light_data[i] & 0xF
			--local light = math.floor(light_data[i] / 16) -- light_data[i] >> 4
			light_data[i] = lightlevel * 16 + sunlight
		end
	end
	vmanip:set_light_data(light_data)
	vmanip:write_to_map(false)
	for i = 1, 6 do
		if
			math.abs(directions[i].x) ~= math.abs(step.x) or
			math.abs(directions[i].y) ~= math.abs(step.y) or
			math.abs(directions[i].z) ~= math.abs(step.z)
		then
			local adjacentraybegpos = vector.add(begpos, directions[i])
			for j = 1, raylength do
				local node = minetest.get_node(adjacentraybegpos)
				if math.floor(node.param1 / 16) < lightlevel then
					minetest.swap_node(adjacentraybegpos, node)
				end
				adjacentraybegpos = vector.add(adjacentraybegpos, step)
			end
		end
	end
	endpos = vector.add(endpos, step)
	local node = minetest.get_node(endpos)
	if math.floor(node.param1 / 16) < lightlevel then
		minetest.swap_node(endpos, node)
	end
end

minetest.register_node("industrial_lights:air_light", {
	drawtype = "airlike",
	paramtype = "light",
	paramtype2 = "none",
	light_source = 14,
	pointable = false,
	sunlight_propagates = true,
	buildable_to = true,
	walkable = false
})

local air_light_cid = minetest.get_content_id("industrial_lights:air_light")

minetest.register_node("industrial_lights:basic_light", {
	drawtype = "normal",
	tiles = {"test1.png", "test2.png", "test3.png", "test4.png", "test5.png", "test6.png"},
	paramtype = "none",
	paramtype2 = "facedir",
	--light_source = 14,
	groups = {cracky = 3},
	on_place = function(itemstack, placer, pointed_thing)
		return minetest.item_place(itemstack, placer, pointed_thing, minetest.dir_to_facedir(placer:get_look_dir(), true))
	end,
	on_construct = function(pos)
		minetest.get_node_timer(pos):set(1, 0)
	end,
	on_timer = function(pos, elapsed)
		local raylength = 16
		local step = vector.multiply(minetest.facedir_to_dir(minetest.get_node(pos).param2), -1)
		local begpos = vector.add(pos, step)
		local cpos = begpos
		for i = 1, raylength do
			local node = minetest.get_node(cpos)
			if minetest.registered_nodes[node.name].paramtype ~= "light" then
				raylength = i
				break
			end
			cpos = vector.add(cpos, step)
		end
		construct_light_via_mapgen(step, begpos, raylength)
		return true
	end,
	on_destruct = function(pos)
		local raylength = 16
		local step = vector.multiply(minetest.facedir_to_dir(minetest.get_node(pos).param2), -1)
		local begpos = vector.add(pos, step)
		local endpos = vector.add(begpos, vector.multiply(step, raylength))
		local minpos, maxpos = {
			x = math.min(begpos.x, endpos.x),
			y = math.min(begpos.y, endpos.y),
			z = math.min(begpos.z, endpos.z)
		}, {
			x = math.max(begpos.x, endpos.x),
			y = math.max(begpos.y, endpos.y),
			z = math.max(begpos.z, endpos.z)
		}
		local vmanip = minetest.get_voxel_manip()
		vmanip:read_from_map(minpos, maxpos)
		vmanip:write_to_map()
	end
})