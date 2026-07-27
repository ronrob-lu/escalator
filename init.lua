-- =============================================================================
-- escalator/init.lua
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Settings  (defined in settingtypes.txt; editable from the main-menu panel)
-- ---------------------------------------------------------------------------

local S = core.settings

local H_SPEED       = tonumber(S:get("escalator_h_speed"))       or 2.5
local V_SPEED       = tonumber(S:get("escalator_v_speed"))       or 3.0
local MAX_STEPS     = tonumber(S:get("escalator_max_stair_length")) or 32
local SCAN_INTERVAL = tonumber(S:get("escalator_timer_interval")) or 1.0
local CACHE_TTL     = 2.0   -- not exposed; internal implementation detail

-- ---------------------------------------------------------------------------
-- Stair detection  (cross-gamepack: MTG, VoxeLibre/MineClone2, etc.)
-- ---------------------------------------------------------------------------
--
-- MTG / Luanti  → nodes are in the "stair" group
-- VoxeLibre     → stair nodes are in the "mcl_stairs_half" group
-- Fallback      → node name contains ":stair" (colon-scoped to avoid false
--                 positives like "signs:to_stairs")

local function is_stair(node_name)
    if not node_name or node_name == "air" or node_name == "ignore" then
        return false
    end
    local def = core.registered_nodes[node_name]
    if not def then return false end
    local groups = def.groups or {}
    if (groups.stair or 0) > 0 then return true end          -- MTG / Luanti
    if (groups.mcl_stairs_half or 0) > 0 then return true end -- VoxeLibre
    if node_name:find(":stair") then return true end          -- scoped fallback
    return false
end

-- ---------------------------------------------------------------------------
-- Direction vectors
-- ---------------------------------------------------------------------------

local ORIENT_VEC = {
    north = { x =  0, z = -1 },
    south = { x =  0, z =  1 },
    east  = { x =  1, z =  0 },
    west  = { x = -1, z =  0 },
}

-- ---------------------------------------------------------------------------
-- Key helpers  (string.format ensures no "1.0" vs "1" mismatch)
-- ---------------------------------------------------------------------------

local function key3(x, y, z)
    return string.format("%d,%d,%d",
        math.floor(x + 0.5),
        math.floor(y + 0.5),
        math.floor(z + 0.5))
end

local function key_pos(p)
    return key3(p.x, p.y, p.z)
end

-- ---------------------------------------------------------------------------
-- Stair-path scanner
-- ---------------------------------------------------------------------------

local function scan_diagonal(sx, sy, sz, ovx, ovz, dir_y)
    local path   = {}
    local misses = 0
    for i = 1, MAX_STEPS do
        local px, py, pz = sx + ovx*i, sy + dir_y*i, sz + ovz*i
        local node = core.get_node_or_nil({ x=px, y=py, z=pz })
        if node and is_stair(node.name) then
            misses = 0
            path[#path+1] = { x=px, y=py, z=pz }
        else
            misses = misses + 1
            if misses >= 2 then break end
        end
    end
    return path
end

--- Try all 4 orientations × 2 vertical directions × 3 Y start offsets.
--- Returns the path that finds the most stair nodes.
local function find_best_path(ctrl_pos)
    local cx, cy, cz = ctrl_pos.x, ctrl_pos.y, ctrl_pos.z
    local best = { path={}, orient="north", dir="up" }

    for _, dy_start in ipairs({ 0, 1, -1 }) do
        local sy = cy + dy_start
        for orient, ov in pairs(ORIENT_VEC) do
            local pu = scan_diagonal(cx, sy, cz, ov.x, ov.z, 1)
            if #pu > #best.path then
                best = { path=pu, orient=orient, dir="up" }
            end
            local pd = scan_diagonal(cx, sy, cz, ov.x, ov.z, -1)
            if #pd > #best.path then
                best = { path=pd, orient=orient, dir="down" }
            end
        end
    end

    return best.path, best.orient, best.dir
end

-- ---------------------------------------------------------------------------
-- Global tables
-- ---------------------------------------------------------------------------

--- Maps key3(stair_pos) → { orient, dir, ctrl_key }
--- Updated by the node timer; read by the globalstep every tick.
local stair_map  = {}

--- Maps key_pos(ctrl_pos) → { path, orient, dir, expires }
local path_cache = {}

-- ---------------------------------------------------------------------------
-- Cache & stair-map management
-- ---------------------------------------------------------------------------

local function clear_stair_map_for(ctrl_key)
    for k, v in pairs(stair_map) do
        if v.ctrl_key == ctrl_key then stair_map[k] = nil end
    end
end

local function invalidate(pos)
    local key = key_pos(pos)
    clear_stair_map_for(key)
    path_cache[key] = nil
end

local function refresh_path(ctrl_pos)
    local key = key_pos(ctrl_pos)
    local now = core.get_gametime()
    local c   = path_cache[key]
    if c and now < c.expires then return c.path, c.orient, c.dir end

    local path, orient, dir = find_best_path(ctrl_pos)
    path_cache[key] = { path=path, orient=orient, dir=dir, expires=now+CACHE_TTL }

    -- Rebuild the stair-map section owned by this controller.
    clear_stair_map_for(key)
    for _, sp in ipairs(path) do
        stair_map[key3(sp.x, sp.y, sp.z)] = { orient=orient, dir=dir, ctrl_key=key }
    end

    -- Update controller infotext.
    local meta = core.get_meta(ctrl_pos)
    if #path > 0 then
        meta:set_string("infotext", string.format(
            "Escalator  |  %s  |  %s  |  %d steps\nRight-click for info",
            string.upper(orient),
            dir == "up" and "UP ▲" or "DOWN ▼",
            #path))
    else
        meta:set_string("infotext",
            "Escalator Controller\n" ..
            "⚠ No stair nodes detected nearby.\n" ..
            "Build a diagonal staircase from this block.")
    end

    return path, orient, dir
end

-- ---------------------------------------------------------------------------
-- Player-to-stair lookup
-- ---------------------------------------------------------------------------
--
-- Player feet Y is ABOVE the stair node integer Y.
-- When transitioning from step i to step i+1, the next stair node's Y
-- is HIGHER than the current player Y, so we must probe ABOVE as well.
--
-- Probe range: +1.0 node above feet … −1.5 nodes below feet.

local PROBE_DY = { 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, -0.75, -1.0, -1.25, -1.5 }

local function escalator_info_at(pos)
    local ix = math.floor(pos.x + 0.5)
    local iz = math.floor(pos.z + 0.5)
    local fy = pos.y

    for _, dy in ipairs(PROBE_DY) do
        local iy  = math.floor(fy + dy)   -- integer node Y
        local key = string.format("%d,%d,%d", ix, iy, iz)
        local info = stair_map[key]
        if info then return info end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- GlobalStep – player transport (runs every server physics tick)
-- ---------------------------------------------------------------------------
--
-- Horizontal always moves in the orient direction.
-- Only vertical uses v_sign so that "down" escalators don't reverse direction.

core.register_globalstep(function(dtime)
    for _, player in ipairs(core.get_connected_players()) do
        local pos = player:get_pos()
        if not pos then goto skip end

        local info = escalator_info_at(pos)
        if not info then goto skip end

        local ov     = ORIENT_VEC[info.orient]
        local v_sign = (info.dir == "up") and 1 or -1

        -- set_pos bypasses physics, so no fighting with gravity or friction.
        player:set_pos({
            x = pos.x + ov.x * H_SPEED * dtime,
            y = pos.y + v_sign * V_SPEED * dtime,
            z = pos.z + ov.z * H_SPEED * dtime,
        })

        -- Also set velocity so the physics engine reinforces direction
        -- between set_pos calls.
        player:set_velocity({
            x = ov.x * H_SPEED,
            y = v_sign * V_SPEED,
            z = ov.z * H_SPEED,
        })

        ::skip::
    end
end)

-- ---------------------------------------------------------------------------
-- Node-timer callback – refresh stair map, move mobs
-- ---------------------------------------------------------------------------

local function on_timer(pos, elapsed)
    if core.get_node(pos).name ~= "escalator:controller" then
        invalidate(pos)
        return false
    end

    local path, orient, dir = refresh_path(pos)

    -- Move non-player entities (mobs) that are standing on stair nodes.
    if #path > 0 then
        local ov     = ORIENT_VEC[orient]
        local v_sign = (dir == "up") and 1 or -1
        local seen   = {}

        for _, sp in ipairs(path) do
            for _, dy in ipairs({ 0.4, 0.9, 1.4 }) do
                local centre = { x=sp.x, y=sp.y+dy, z=sp.z }
                for _, obj in ipairs(core.get_objects_inside_radius(centre, 1.2)) do
                    if not obj:is_player() then
                        local uid = tostring(obj)
                        if not seen[uid] then
                            seen[uid] = true
                            local p   = obj:get_pos()
                            local vel = obj:get_velocity()
                            if p and vel then
                                -- Modern mob: set velocity.
                                obj:set_velocity({
                                    x = ov.x * H_SPEED,
                                    y = v_sign * V_SPEED,
                                    z = ov.z * H_SPEED,
                                })
                            elseif p then
                                -- Legacy mob: direct position nudge.
                                obj:set_pos({
                                    x = p.x + ov.x * H_SPEED * elapsed,
                                    y = p.y + v_sign * V_SPEED * elapsed,
                                    z = p.z + ov.z * H_SPEED * elapsed,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    return true  -- reschedule
end

-- ---------------------------------------------------------------------------
-- Node definition
-- ---------------------------------------------------------------------------

core.register_node("escalator:controller", {
    description = "Escalator Controller\n" ..
                  "Place at the base of any diagonal staircase.\n" ..
                  "Direction and orientation are detected automatically.",
    tiles = {
        "escalator_controller.png",
        "escalator_controller.png",
        "escalator_controller.png",
        "escalator_controller.png",
        "escalator_controller.png",
        "escalator_controller_front.png",
    },
    groups            = { cracky=1, oddly_breakable_by_hand=1 },
    sounds            = default and default.node_sound_metal_defaults() or {},
    paramtype2        = "facedir",
    is_ground_content = false,

    on_construct = function(pos)
        core.get_meta(pos):set_string("infotext",
            "Escalator Controller  |  Scanning for stairs…")
        core.get_node_timer(pos):start(SCAN_INTERVAL)
    end,

    on_destruct = function(pos)
        invalidate(pos)
        local t = core.get_node_timer(pos)
        if t then t:stop() end
    end,

    on_timer = on_timer,

    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        if not clicker or not clicker:is_player() then return itemstack end
        -- Force an immediate fresh scan.
        invalidate(pos)
        refresh_path(pos)
        core.chat_send_player(
            clicker:get_player_name(),
            "[Escalator] " ..
            core.get_meta(pos):get_string("infotext"):gsub("\n", "  |  "))
        return itemstack
    end,
})

-- ---------------------------------------------------------------------------
-- Craft recipe
-- ---------------------------------------------------------------------------

core.register_craft({
    output = "escalator:controller",
    recipe = {
        { "",                    "default:mese_crystal",   ""                    },
        { "default:steel_ingot", "default:steel_ingot",    "default:steel_ingot" },
        { "default:steel_ingot", "",                       "default:steel_ingot" },
    },
})

-- ---------------------------------------------------------------------------
-- Dependency guard
-- ---------------------------------------------------------------------------

core.register_on_mods_loaded(function()
    local count = 0
    for name, _ in pairs(core.registered_nodes) do
        if is_stair(name) then count = count + 1 end
    end
    if count == 0 then
        core.log("warning",
            "[escalator] No stair nodes detected in any registered mod. " ..
            "Escalator transport will not activate.")
    else
        core.log("action",
            "[escalator] Detected " .. count .. " stair node(s) across loaded mods.")
    end
end)

-- ---------------------------------------------------------------------------
-- Debug command  (/escalator_info – look at controller or stand on stair)
-- ---------------------------------------------------------------------------

core.register_chatcommand("escalator_info", {
    description = "Report escalator state at the controller you are looking at, " ..
                  "or the stair you are standing on.",
    privs = { interact = true },
    func = function(name, param)
        local player = core.get_player_by_name(name)
        if not player then return false, "Player not found." end

        -- Check stair under player first.
        local ppos = player:get_pos()
        local info = ppos and escalator_info_at(ppos)
        if info then
            return true, string.format(
                "Standing on escalator stair  orient=%s  dir=%s",
                info.orient, info.dir)
        end

        -- Then raycast to controller.
        local eye  = ppos and { x=ppos.x, y=ppos.y+1.5, z=ppos.z } or player:get_pos()
        local look = player:get_look_dir()
        local far  = { x=eye.x+look.x*12, y=eye.y+look.y*12, z=eye.z+look.z*12 }

        for pt in core.raycast(eye, far, false, false) do
            if pt.type == "node" then
                local n = core.get_node(pt.under)
                if n.name == "escalator:controller" then
                    local cpos = pt.under
                    invalidate(cpos)
                    local path, orient, dir = refresh_path(cpos)
                    return true, string.format(
                        "Controller @ %s  orient=%s  dir=%s  steps=%d",
                        core.pos_to_string(cpos), orient, dir, #path)
                end
            end
        end

        return false,
            "Look at an escalator:controller, or stand on a stair node " ..
            "that belongs to an escalator."
    end,
})

-- ---------------------------------------------------------------------------
-- Loaded
-- ---------------------------------------------------------------------------

core.log("action",
    "[escalator] loaded.  Stair detection: group-based (MTG + VoxeLibre compatible)")
