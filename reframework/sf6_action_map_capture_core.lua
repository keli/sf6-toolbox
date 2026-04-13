local FINAL_BASE_DIR = "sf6-toolbox"
local ALIASES_PATH = "sf6-toolbox/sf6_character_aliases.json"
local OUTPUT_DIR = "sf6-toolbox/action_maps_measured"

local BTN = {
    UP = 1,
    DOWN = 2,
    LEFT = 4,
    RIGHT = 8,
    LP = 16,
    MP = 32,
    HP = 64,
    LK = 128,
    MK = 256,
    HK = 512,
}

local DIR_ALL = BTN.UP | BTN.DOWN | BTN.LEFT | BTN.RIGHT

local state = {
    self_slot = 0,
    enemy_slot = 1,
    chara_id = -1,
    chara_dir = nil,
    final_path = nil,
    last_status = "",
    loaded = false,
    running = false,
    done = false,
    move_index = 1,
    step_index = 1,
    step_frames_left = 0,
    step_wait_timeout = 0,
    phase = "idle",
    current_move = nil,
    pre_approach_active = false,
    pre_approach_step_index = 1,
    pre_approach_step_frames_left = 0,
    pre_approach_wait_left = 0,
    sequence_index = 1,
    baseline_action_id = -1,
    observed_ids = {},
    dir_frames = 2,
    press_frames = 2,
    startup_wait_frames = 45,
    completion_wait_frames = 180,
    idle_confirm_frames = 6,
    startup_wait_left = 0,
    completion_wait_left = 0,
    idle_confirm_left = 0,
    between_move_frames = 14,
    pre_approach_enabled = true,
    pre_approach_chance_percent = 60,
    pre_approach_dir_frames = 2,
    pre_approach_pause_frames = 1,
    pre_approach_settle_frames = 8,
    between_frames_left = 0,
    run_moves = {},
    skipped_moves = {},
    last_self_action_id = -1,
    last_output_path = "",
    aliases = nil,
    aliases_error = nil,
    pending_inject = { slot = 0, mask = 0, frames_left = 0 },
    inject_hook_ready = false,
    inject_hook_error = "",
    inject_last_note = "",
    capture_context = "auto",
    hp_field_by_slot = {},
    enemy_baseline_action_id = -1,
    enemy_action_changed = false,
    enemy_hp_before = nil,
    enemy_hp_after = nil,
    enemy_hp_min = nil,
    enemy_damage_seen = false,
    last_detected_context = "unlabeled",
    batch_run_target = 5,
    batch_run_remaining = 0,
    batch_run_total = 0,
    batch_active = false,
    force_new_output_slot = false,
}

math.randomseed(os.time())

local function to_int(v)
    if type(v) == "number" then
        return math.floor(v)
    end
    return nil
end

local function read_sfix(v)
    if not v then
        return 0
    end

    if type(v.ToFloat) == "function" then
        local ok, f = pcall(v.ToFloat, v)
        if ok and type(f) == "number" then
            return f
        end
    end

    if type(v.v) == "number" then
        local raw = v.v
        local v16 = raw / 65536.0
        local v100 = raw / 6553600.0
        if math.abs(v16) <= 100000 then
            return v16
        end
        return v100
    end

    return 0
end

local function get_player_mgr()
    local g_battle = sdk.find_type_definition("gBattle")
    if not g_battle then
        return nil
    end
    local field = g_battle:get_field("Player")
    if not field then
        return nil
    end
    local ok, mgr = pcall(field.get_data, field, nil)
    if ok then
        return mgr
    end
    return nil
end

local function get_cplayer(slot)
    local mgr = get_player_mgr()
    if not mgr then
        return nil
    end
    local ok, cp = pcall(mgr.call, mgr, "getPlayer", slot)
    if ok then
        return cp
    end
    return nil
end

local function get_chara_id(slot)
    local mgr = get_player_mgr()
    if not mgr or not mgr.mPlayerType then
        return nil
    end
    local item = mgr.mPlayerType[slot]
    if not item then
        return nil
    end
    if type(item.mValue) == "number" then
        return math.floor(item.mValue)
    end
    local ok, val = pcall(function()
        return item:get_Value()
    end)
    if ok and type(val) == "number" then
        return math.floor(val)
    end
    return nil
end

local function get_engine_by_slot(slot)
    local g_battle = sdk.find_type_definition("gBattle")
    if not g_battle then
        return nil
    end

    local rb_field = g_battle:get_field("Rollback")
    if not rb_field then
        return nil
    end

    local ok_rb, rollback = pcall(rb_field.get_data, rb_field)
    if not ok_rb or not rollback then
        return nil
    end

    local ok_engine, latest = pcall(rollback.call, rollback, "GetLatestEngine")
    if not ok_engine or not latest or not latest.ActEngines then
        return nil
    end

    local wrapper = latest.ActEngines[slot]
    return wrapper and wrapper._Parent and wrapper._Parent._Engine or nil
end

local function get_action_id(slot)
    local engine = get_engine_by_slot(slot)
    if not engine then
        return -1
    end
    local ok, act = pcall(engine.get_ActionID, engine)
    if ok and type(act) == "number" then
        return math.floor(act)
    end
    return -1
end

local function get_scr_pos_x(cp)
    if not cp then
        return nil
    end
    local ok, v = pcall(cp.call, cp, "get_scr_pos_x")
    if not ok then
        return nil
    end
    return read_sfix(v)
end

local function facing_is_left(self_cp, enemy_cp)
    local sx = get_scr_pos_x(self_cp)
    local ex = get_scr_pos_x(enemy_cp)
    if sx == nil or ex == nil then
        return false
    end
    return sx > ex
end

local function mirror_digit(d)
    if d == 1 then
        return 3
    end
    if d == 3 then
        return 1
    end
    if d == 4 then
        return 6
    end
    if d == 6 then
        return 4
    end
    if d == 7 then
        return 9
    end
    if d == 9 then
        return 7
    end
    return d
end

local function digit_to_dir_mask(d)
    if d == 1 then
        return BTN.DOWN | BTN.LEFT
    elseif d == 2 then
        return BTN.DOWN
    elseif d == 3 then
        return BTN.DOWN | BTN.RIGHT
    elseif d == 4 then
        return BTN.LEFT
    elseif d == 5 then
        return 0
    elseif d == 6 then
        return BTN.RIGHT
    elseif d == 7 then
        return BTN.UP | BTN.LEFT
    elseif d == 8 then
        return BTN.UP
    elseif d == 9 then
        return BTN.UP | BTN.RIGHT
    end
    return 0
end

local BUTTON_MASKS = {
    LP = BTN.LP,
    MP = BTN.MP,
    HP = BTN.HP,
    LK = BTN.LK,
    MK = BTN.MK,
    HK = BTN.HK,
    P = BTN.LP,
    K = BTN.LK,
    PP = BTN.LP | BTN.MP,
    KK = BTN.LK | BTN.MK,
    LPLK = BTN.LP | BTN.LK,
    MPMK = BTN.MP | BTN.MK,
    HPHK = BTN.HP | BTN.HK,
    PPPKKK = BTN.LP | BTN.MP | BTN.HP | BTN.LK | BTN.MK | BTN.HK,
}

local BUTTON_TOKEN_PARTS = { "LP", "MP", "HP", "LK", "MK", "HK", "P", "K" }

local function parse_button_token(token)
    if type(token) ~= "string" or token == "" then
        return nil
    end

    local direct = BUTTON_MASKS[token]
    if direct then
        return direct
    end

    local i = 1
    local out = 0
    while i <= #token do
        local matched = false
        for _, part in ipairs(BUTTON_TOKEN_PARTS) do
            if token:sub(i, i + #part - 1) == part then
                local part_mask = BUTTON_MASKS[part]
                if not part_mask then
                    return nil
                end
                out = out | part_mask
                i = i + #part
                matched = true
                break
            end
        end
        if not matched then
            return nil
        end
    end
    return out
end

local function get_field_number(obj, td, name)
    local f = td:get_field(name)
    if not f then
        return 0
    end
    local ok, v = pcall(f.get_data, f, obj)
    if ok and type(v) == "number" then
        return math.floor(v)
    end
    return 0
end

local function inject_mask(slot, mask)
    if not mask or mask == 0 then
        return false
    end

    local cp = get_cplayer(slot)
    if not cp then
        return false
    end

    local td = cp:get_type_definition()
    if not td then
        return false
    end

    local dir_mask = mask & DIR_ALL
    local atk_mask = mask & ~DIR_ALL
    local input_mask = (dir_mask | atk_mask) & 0xFFFF

    local targets = {
        { name = "pl_input_new", bits = input_mask },
        { name = "pl_input_now", bits = input_mask },
        { name = "pl_sw_new", bits = atk_mask },
        { name = "pl_sw_now", bits = atk_mask },
    }

    local wrote = false
    for _, row in ipairs(targets) do
        local f = td:get_field(row.name)
        if f then
            local cur = get_field_number(cp, td, row.name)
            local new_val = (cur | row.bits) & 0xFFFF
            local ok = pcall(function()
                cp[row.name] = new_val
            end)
            if ok then
                wrote = true
            end
        end
    end

    return wrote
end

local function find_method_by_name(td, exact_sig, bare_name)
    local m = td:get_method(exact_sig)
    if m then
        return m
    end

    m = td:get_method(bare_name)
    if m then
        return m
    end

    local ok, methods = pcall(td.get_methods, td)
    if not ok or not methods then
        return nil
    end

    for _, mm in ipairs(methods) do
        local ok_name, name = pcall(mm.get_name, mm)
        if ok_name and name == bare_name then
            return mm
        end
    end

    return nil
end

local function try_inject_for_obj(self_obj, tag)
    local p = state.pending_inject
    if p.mask == 0 or p.frames_left <= 0 then
        return
    end
    if not self_obj then
        return
    end

    local target_obj = get_cplayer(p.slot)
    if not target_obj then
        state.inject_last_note = "[Inject FAIL] get_cplayer failed"
        p.mask = 0
        p.frames_left = 0
        return
    end

    local is_target = false
    local ok_a, addr_a = pcall(target_obj.get_address, target_obj)
    local ok_b, addr_b = pcall(self_obj.get_address, self_obj)
    if ok_a and ok_b and addr_a and addr_b then
        is_target = (addr_a == addr_b)
    else
        is_target = (self_obj == target_obj)
    end
    if not is_target then
        return
    end

    local ok = inject_mask(p.slot, p.mask)
    state.inject_last_note = string.format(
        "[Inject@%s %s] slot=%d mask=0x%X remain=%d",
        tag,
        ok and "OK" or "FAIL",
        p.slot,
        p.mask,
        p.frames_left
    )
    if ok and tag == "pl_input_sub:post" then
        p.frames_left = p.frames_left - 1
        if p.frames_left <= 0 then
            p.mask = 0
            p.frames_left = 0
        end
    end
end

local function install_inject_hooks()
    if state.inject_hook_ready then
        return true
    end

    local td = sdk.find_type_definition("nBattle.cPlayer")
    if not td then
        state.inject_hook_error = "nBattle.cPlayer type not found"
        return false
    end

    local pre_self = nil
    local pre = function(args)
        pre_self = sdk.to_managed_object(args[2])
        try_inject_for_obj(pre_self, "pl_input_sub:pre")
    end
    local post = function(retval)
        try_inject_for_obj(pre_self, "pl_input_sub:post")
        pre_self = nil
        return retval
    end

    local method = find_method_by_name(td, "pl_input_sub(nBattle.INPUT_ATTR)", "pl_input_sub")
    if not method then
        state.inject_hook_error = "pl_input_sub method not found"
        return false
    end

    local ok, err = pcall(sdk.hook, method, pre, post)
    if not ok then
        state.inject_hook_error = "hook err: " .. tostring(err)
        return false
    end

    state.inject_hook_ready = true
    state.inject_hook_error = ""
    return true
end

local function normalize_cmd(raw)
    if type(raw) ~= "string" then
        return nil, "missing_num_cmd"
    end

    local function parse_single_cmd(raw_piece)
        local u_piece = string.upper(tostring(raw_piece or ""))
        local compact_piece = u_piece:gsub("%b()", ""):gsub("%s+", "")

        if compact_piece:match("^MPMK/66") then
            return {
                raw = raw_piece,
                base = "MPMK/66",
                motion = "66",
                button_token = "MPMK",
                button_mask = BUTTON_MASKS.MPMK,
                execution_mode = "hold_button_then_double_forward",
            }, nil
        end

        local base = u_piece
        local slash = base:find("/", 1, true)
        if slash then
            base = base:sub(1, slash - 1)
        end

        base = base:gsub("%b()", "")
        base = base:gsub("%s+", "")
        base = base:gsub("%.", "")
        if base:sub(1, 1) == "J" then
            base = "8" .. base:sub(2)
        end
        if base == "" then
            return nil, "empty_after_cleanup"
        end

        if not base:match("^[1-9A-Z]+$") then
            return nil, "unsupported_tokens"
        end

        local motion, token = base:match("^(%d*)([A-Z]+)$")
        if not token then
            return nil, "cannot_parse"
        end

        if motion == "" then
            motion = "5"
        end

        for i = 1, #motion do
            local c = motion:sub(i, i)
            if c < "1" or c > "9" then
                return nil, "invalid_motion_digit"
            end
        end

        local button_mask = parse_button_token(token)
        if not button_mask then
            return nil, "unsupported_button_token:" .. token
        end

        return {
            raw = raw_piece,
            base = base,
            motion = motion,
            button_token = token,
            button_mask = button_mask,
        }, nil
    end

    local u = string.upper(raw)

    if u:find(">", 1, true) then
        local seq = {}
        for piece in u:gmatch("[^>]+") do
            local trimmed = piece:gsub("^%s+", ""):gsub("%s+$", "")
            if trimmed ~= "" then
                local sub_cmd, sub_err = parse_single_cmd(trimmed)
                if not sub_cmd then
                    return nil, "sequence_part_" .. tostring(sub_err)
                end
                table.insert(seq, sub_cmd)
            end
        end

        if #seq == 0 then
            return nil, "empty_sequence"
        end
        if #seq == 1 then
            return seq[1], nil
        end

        return {
            raw = raw,
            base = u,
            execution_mode = "sequence",
            sequence = seq,
        }, nil
    end

    return parse_single_cmd(raw)
end

local function load_aliases()
    if state.aliases ~= nil or state.aliases_error ~= nil then
        return state.aliases, state.aliases_error
    end

    if not (json and json.load_file) then
        state.aliases = nil
        state.aliases_error = "json.load_file_unavailable"
        return nil, state.aliases_error
    end

    local ok, data = pcall(json.load_file, ALIASES_PATH)
    if not ok then
        state.aliases = nil
        state.aliases_error = string.format("aliases_load_failed:path=%s err=%s", ALIASES_PATH, tostring(data))
        return nil, state.aliases_error
    end

    if type(data) ~= "table" then
        state.aliases = nil
        state.aliases_error = string.format("aliases_invalid_root_type:path=%s type=%s", ALIASES_PATH, type(data))
        return nil, state.aliases_error
    end

    if type(data.by_id) ~= "table" then
        state.aliases = nil
        state.aliases_error = string.format("aliases_missing_by_id:path=%s", ALIASES_PATH)
        return nil, state.aliases_error
    end

    state.aliases = data.by_id
    state.aliases_error = nil
    return state.aliases, nil
end

local function chara_dir_from_id(chara_id)
    local n = to_int(chara_id)
    if not n then
        return nil, "invalid_chara_id"
    end
    local key = string.format("%03d", n)
    local aliases, alias_err = load_aliases()
    if not aliases then
        return nil, alias_err or "aliases_unavailable"
    end
    local alias = aliases[key] or aliases[tostring(n)]
    if type(alias) == "string" and alias ~= "" then
        return alias, nil
    end
    return nil, string.format("missing_alias_for_chara_id:%s path=%s", key, ALIASES_PATH)
end

local function move_sort_key(move)
    local idx = tonumber(move.sort_index)
    if not idx then
        idx = 999999
    end
    return string.format("%09d|%s", idx, tostring(move.move_name or ""))
end

local function load_moves_for_character(chara_id)
    local dir, dir_err = chara_dir_from_id(chara_id)
    if not dir then
        return false, dir_err or "missing_alias_for_chara_id"
    end

    local final_path = string.format("%s/%s/final.json", FINAL_BASE_DIR, dir)
    local ok, final_json = pcall(json.load_file, final_path)
    if not ok or type(final_json) ~= "table" then
        return false, "failed_to_load_final_json:" .. tostring(final_path)
    end

    local moves_root = final_json.moves
    if type(moves_root) ~= "table" then
        return false, "final_json_moves_missing"
    end

    local runnable = {}
    local skipped = {}

    local categories = {}
    for cat, _ in pairs(moves_root) do
        categories[#categories + 1] = cat
    end
    table.sort(categories)

    for _, category in ipairs(categories) do
        local row = moves_root[category]
        if type(row) == "table" then
            for move_key, move in pairs(row) do
                if type(move) == "table" then
                    local move_name = tostring(move.moveName or move_key)
                    local num_cmd = move.numCmd
                    local parsed, reason = normalize_cmd(num_cmd)
                    local record = {
                        category = tostring(category),
                        move_key = tostring(move_key),
                        move_name = move_name,
                        num_cmd = num_cmd,
                        sort_index = tonumber(move.i) or 999999,
                    }

                    if parsed then
                        record.command = parsed
                        record.status = "pending"
                        record.observed_action_ids = {}
                        record.observed_action_ids_by_context = {}
                        record.primary_action_id = nil
                        runnable[#runnable + 1] = record
                    else
                        record.status = "skipped"
                        record.skip_reason = reason
                        skipped[#skipped + 1] = record
                    end
                end
            end
        end
    end

    table.sort(runnable, function(a, b)
        return move_sort_key(a) < move_sort_key(b)
    end)
    table.sort(skipped, function(a, b)
        return move_sort_key(a) < move_sort_key(b)
    end)

    state.chara_id = chara_id
    state.chara_dir = dir
    state.final_path = final_path
    state.run_moves = runnable
    state.skipped_moves = skipped
    state.loaded = true
    state.running = false
    state.done = false
    state.move_index = 1
    state.phase = "idle"
    state.current_move = nil
    state.last_status = string.format(
        "Loaded %d runnable moves, skipped %d (%s)",
        #runnable,
        #skipped,
        dir
    )

    return true, nil
end

local function reset_runtime_progress()
    for _, row in ipairs(state.run_moves) do
        row.status = "pending"
        row.observed_action_ids = {}
        row.observed_action_ids_by_context = {}
        row.primary_action_id = nil
    end
    state.running = false
    state.done = false
    state.move_index = 1
    state.step_index = 1
    state.step_frames_left = 0
    state.step_wait_timeout = 0
    state.phase = "idle"
    state.current_move = nil
    state.pre_approach_active = false
    state.pre_approach_step_index = 1
    state.pre_approach_step_frames_left = 0
    state.pre_approach_wait_left = 0
    state.sequence_index = 1
    state.baseline_action_id = -1
    state.observed_ids = {}
    state.enemy_baseline_action_id = -1
    state.enemy_action_changed = false
    state.enemy_hp_before = nil
    state.enemy_hp_after = nil
    state.enemy_hp_min = nil
    state.enemy_damage_seen = false
    state.last_detected_context = "unlabeled"
    state.startup_wait_left = 0
    state.completion_wait_left = 0
    state.idle_confirm_left = 0
    state.between_frames_left = 0
    state.pending_inject.mask = 0
    state.pending_inject.frames_left = 0
end

local function sorted_ids_from_set(set_tbl)
    local out = {}
    for id, v in pairs(set_tbl or {}) do
        if v then
            out[#out + 1] = tonumber(id)
        end
    end
    table.sort(out)
    return out
end

local function get_forward_dir_mask()
    local self_cp = get_cplayer(state.self_slot)
    local enemy_cp = get_cplayer(state.enemy_slot)
    local facing_left = facing_is_left(self_cp, enemy_cp)
    local d = facing_left and 4 or 6
    return digit_to_dir_mask(d)
end

local function read_field_number_or_nil(obj, td, field_name)
    if not obj or not td or type(field_name) ~= "string" then
        return nil
    end
    local f = td:get_field(field_name)
    if not f then
        return nil
    end
    local ok, v = pcall(f.get_data, f, obj)
    if ok and type(v) == "number" then
        return tonumber(v)
    end
    return nil
end

local function discover_hp_field(slot)
    if state.hp_field_by_slot[slot] ~= nil then
        return state.hp_field_by_slot[slot]
    end

    local cp = get_cplayer(slot)
    if not cp then
        state.hp_field_by_slot[slot] = false
        return nil
    end

    local td = cp:get_type_definition()
    if not td then
        state.hp_field_by_slot[slot] = false
        return nil
    end

    local preferred = {
        "vital",
        "vital_now",
        "life",
        "hp",
    }

    for _, name in ipairs(preferred) do
        local v = read_field_number_or_nil(cp, td, name)
        if v ~= nil then
            state.hp_field_by_slot[slot] = name
            return name
        end
    end

    local ok, fields = pcall(td.get_fields, td)
    if not ok or type(fields) ~= "table" then
        state.hp_field_by_slot[slot] = false
        return nil
    end

    for _, f in ipairs(fields) do
        if f and not f:is_static() then
            local name = string.lower(tostring(f:get_name() or ""))
            if name:find("vital", 1, true) or name:find("life", 1, true) or name:find("hp", 1, true) then
                local vv = read_field_number_or_nil(cp, td, f:get_name())
                if vv ~= nil then
                    state.hp_field_by_slot[slot] = f:get_name()
                    return f:get_name()
                end
            end
        end
    end

    state.hp_field_by_slot[slot] = false
    return nil
end

local function read_player_hp(slot)
    local hp_field = discover_hp_field(slot)
    if not hp_field then
        return nil
    end
    local cp = get_cplayer(slot)
    if not cp then
        return nil
    end
    local td = cp:get_type_definition()
    if not td then
        return nil
    end
    return read_field_number_or_nil(cp, td, hp_field)
end

local function is_capture_complete(data)
    if type(data) ~= "table" then
        return false
    end
    local stats = data.stats
    if type(stats) ~= "table" then
        return false
    end

    local runnable = tonumber(stats.runnable_moves) or 0
    local mapped = tonumber(stats.mapped_moves) or 0
    local no_action = tonumber(stats.no_action_moves) or 0

    if runnable <= 0 then
        return false
    end

    return (mapped + no_action) >= runnable
end

local function choose_output_path(chara_id, force_new)
    local last_idx = 0
    local last_data = nil

    if not (json and json.load_file) then
        local idx = 1
        local path = string.format("%s/sf6_action_map_capture_chara_%03d_run_%02d.json", OUTPUT_DIR, chara_id or 0, idx)
        return idx, path, "json_unavailable_default_slot"
    end

    for i = 1, 999 do
        local path = string.format("%s/sf6_action_map_capture_chara_%03d_run_%02d.json", OUTPUT_DIR, chara_id or 0, i)
        local ok, data = pcall(json.load_file, path)
        if ok and type(data) == "table" then
            last_idx = i
            last_data = data
        end
    end

    if last_idx == 0 then
        local idx = 1
        local path = string.format("%s/sf6_action_map_capture_chara_%03d_run_%02d.json", OUTPUT_DIR, chara_id or 0, idx)
        return idx, path, "new_slot_01"
    end

    if force_new then
        local idx = last_idx + 1
        local path = string.format("%s/sf6_action_map_capture_chara_%03d_run_%02d.json", OUTPUT_DIR, chara_id or 0, idx)
        return idx, path, "force_new_slot"
    end

    if is_capture_complete(last_data) then
        local idx = last_idx + 1
        local path = string.format("%s/sf6_action_map_capture_chara_%03d_run_%02d.json", OUTPUT_DIR, chara_id or 0, idx)
        return idx, path, "previous_complete_new_slot"
    end

    local idx = last_idx
    local path = string.format("%s/sf6_action_map_capture_chara_%03d_run_%02d.json", OUTPUT_DIR, chara_id or 0, idx)
    return idx, path, "previous_incomplete_reuse_slot"
end

local function save_results()
    if not (json and json.dump_file) then
        state.last_status = "json.dump_file unavailable"
        return false
    end

    if fs and type(fs.create_directories) == "function" then
        pcall(fs.create_directories, OUTPUT_DIR)
    elseif fs and type(fs.create_directory) == "function" then
        pcall(fs.create_directory, OUTPUT_DIR)
    end

    local mapped = 0
    local no_action = 0
    local action_to_moves = {}
    local action_to_moves_by_context = {}

    for _, row in ipairs(state.run_moves) do
        local ids = row.observed_action_ids or {}
        if #ids > 0 then
            mapped = mapped + 1
            for _, id in ipairs(ids) do
                local key = tostring(id)
                action_to_moves[key] = action_to_moves[key] or {}
                action_to_moves[key][#action_to_moves[key] + 1] = row.move_name
            end
        elseif row.status == "no_action" then
            no_action = no_action + 1
        end

        local by_ctx = row.observed_action_ids_by_context
        if type(by_ctx) == "table" then
            for ctx, ctx_ids in pairs(by_ctx) do
                if type(ctx) == "string" and type(ctx_ids) == "table" then
                    action_to_moves_by_context[ctx] = action_to_moves_by_context[ctx] or {}
                    local ctx_map = action_to_moves_by_context[ctx]
                    for _, id in ipairs(ctx_ids) do
                        local key = tostring(id)
                        ctx_map[key] = ctx_map[key] or {}
                        ctx_map[key][#ctx_map[key] + 1] = row.move_name
                    end
                end
            end
        end
    end

    local out = {
        schema_version = 1,
        generated_at = os.date("%Y-%m-%d %H:%M:%S"),
        chara_id = state.chara_id,
        chara_dir = state.chara_dir,
        source_final = state.final_path,
        run_config = {
            dir_frames = state.dir_frames,
            press_frames = state.press_frames,
            startup_wait_frames = state.startup_wait_frames,
            completion_wait_frames = state.completion_wait_frames,
            idle_confirm_frames = state.idle_confirm_frames,
            between_move_frames = state.between_move_frames,
            self_slot = state.self_slot,
            capture_context = "auto",
            batch_run_total = state.batch_run_total,
            batch_run_remaining_at_save = state.batch_run_remaining,
        },
        stats = {
            runnable_moves = #state.run_moves,
            skipped_moves = #state.skipped_moves,
            mapped_moves = mapped,
            no_action_moves = no_action,
        },
        moves = state.run_moves,
        skipped = state.skipped_moves,
        action_to_moves = action_to_moves,
        action_to_moves_by_context = action_to_moves_by_context,
    }

    local run_index, out_path, slot_reason = choose_output_path(state.chara_id or 0, state.force_new_output_slot)
    out.run_index = run_index
    out.run_slot_reason = slot_reason

    local ok, err = pcall(json.dump_file, out_path, out)
    if ok and err ~= false then
        state.last_output_path = out_path
        state.last_status = string.format("Saved: %s (run=%02d, mode=%s)", out_path, run_index or 0, tostring(slot_reason))
        return true
    end

    state.last_status = "Save failed: " .. tostring(err)
    return false
end

local function prepare_move_for_execution(move)
    state.current_move = move
    state.phase = "input"
    state.pre_approach_active = false
    state.pre_approach_step_index = 1
    state.pre_approach_step_frames_left = 0
    state.pre_approach_wait_left = 0
    state.sequence_index = 1
    state.step_index = 1
    state.step_frames_left = 0
    state.step_wait_timeout = 0
    state.observed_ids = {}
    state.baseline_action_id = get_action_id(state.self_slot)
    state.enemy_baseline_action_id = get_action_id(state.enemy_slot)
    state.enemy_action_changed = false
    state.enemy_hp_before = read_player_hp(state.enemy_slot)
    state.enemy_hp_after = state.enemy_hp_before
    state.enemy_hp_min = state.enemy_hp_before
    state.enemy_damage_seen = false
    state.startup_wait_left = 0
    state.completion_wait_left = 0
    state.idle_confirm_left = 0
    state.pending_inject.mask = 0
    state.pending_inject.frames_left = 0

    if state.pre_approach_enabled then
        local chance = math.max(0, math.min(100, tonumber(state.pre_approach_chance_percent) or 0))
        if chance > 0 and math.random(1, 100) <= chance then
            state.pre_approach_active = true
            state.phase = "pre_approach"
            state.pre_approach_step_index = 1
            state.pre_approach_step_frames_left = 0
            state.pre_approach_wait_left = 0
        end
    end

    move.status = "running"
    move.observed_action_ids = {}
    move.observed_action_ids_by_context = move.observed_action_ids_by_context or {}
    move.primary_action_id = nil
end

local function get_active_cmd(move)
    local root = move and move.command or nil
    if not root then
        return nil
    end
    if root.execution_mode == "sequence" then
        local seq = root.sequence
        if type(seq) ~= "table" then
            return nil
        end
        return seq[state.sequence_index]
    end
    return root
end

local function build_step_mask(cmd, facing_left_now, step_idx)
    if not cmd then
        return 0, false
    end

    if cmd.execution_mode == "hold_button_then_double_forward" then
        local d = facing_left_now and 4 or 6
        local dir_mask = digit_to_dir_mask(d)
        local hold = cmd.button_mask or 0
        if step_idx == 1 then
            return hold, false
        elseif step_idx == 2 then
            return (hold | dir_mask), false
        elseif step_idx == 3 then
            return hold, false
        elseif step_idx == 4 then
            return (hold | dir_mask), false
        end
        return 0, false
    end

    local motion = cmd.motion
    local motion_len = #motion
    if step_idx <= motion_len then
        local d = tonumber(motion:sub(step_idx, step_idx))
        if facing_left_now then
            d = mirror_digit(d)
        end
        return digit_to_dir_mask(d), false
    end

    if step_idx == (motion_len + 1) then
        local last_d = tonumber(motion:sub(motion_len, motion_len))
        if facing_left_now then
            last_d = mirror_digit(last_d)
        end
        local dir_mask = digit_to_dir_mask(last_d)
        local press_mask = cmd.button_mask or 0
        return (dir_mask | press_mask), true
    end

    return 0, false
end

local function get_total_steps(cmd)
    if not cmd then
        return 0
    end
    if cmd.execution_mode == "hold_button_then_double_forward" then
        return 4
    end
    return #cmd.motion + 1
end

local function get_step_frames(cmd, step_idx)
    if cmd and cmd.execution_mode == "hold_button_then_double_forward" then
        if step_idx == 1 then
            return math.max(1, state.press_frames)
        end
        if step_idx == 3 then
            return 1
        end
        return math.max(1, state.dir_frames)
    end

    local step_is_press = (step_idx == (#cmd.motion + 1))
    return step_is_press and math.max(1, state.press_frames) or math.max(1, state.dir_frames)
end

local function resolve_auto_capture_context()
    if state.enemy_damage_seen then
        return "on_hit"
    end

    if state.enemy_action_changed then
        return "on_block"
    end

    return "whiff"
end

local function finalize_current_move(reason)
    local move = state.current_move
    if not move then
        return
    end

    local ids = sorted_ids_from_set(state.observed_ids)
    move.observed_action_ids = ids
    move.primary_action_id = ids[1]
    move.observed_action_ids_by_context = move.observed_action_ids_by_context or {}
    local detected_context = resolve_auto_capture_context()
    state.last_detected_context = detected_context
    move.observed_action_ids_by_context[detected_context] = ids
    move.capture_context_detected = detected_context

    if #ids > 0 then
        move.status = "mapped"
    elseif reason and reason ~= "" then
        move.status = reason
    else
        move.status = "no_action"
    end

    state.current_move = nil
    state.phase = "between"
    state.between_frames_left = state.between_move_frames
    state.move_index = state.move_index + 1
end

local function tick_runner()
    if not state.running or not state.loaded then
        return
    end

    state.last_self_action_id = get_action_id(state.self_slot)

    if state.move_index > #state.run_moves then
        state.running = false
        state.done = true
        local saved = save_results()
        if state.batch_active and saved then
            state.batch_run_remaining = math.max(0, (tonumber(state.batch_run_remaining) or 0) - 1)
            if state.batch_run_remaining > 0 then
                reset_runtime_progress()
                state.force_new_output_slot = true
                state.running = true
                state.done = false
                state.last_status = string.format(
                    "Batch next run started (%d/%d left)",
                    state.batch_run_remaining,
                    state.batch_run_total
                )
            else
                state.batch_active = false
                state.force_new_output_slot = false
                state.last_status = string.format("Batch capture completed (%d runs)", state.batch_run_total)
            end
        else
            state.batch_active = false
            state.force_new_output_slot = false
        end
        return
    end

    if state.phase == "idle" then
        prepare_move_for_execution(state.run_moves[state.move_index])
        return
    end

    if state.phase == "between" then
        state.between_frames_left = state.between_frames_left - 1
        if state.between_frames_left <= 0 then
            state.phase = "idle"
        end
        return
    end

    local move = state.current_move
    if not move then
        state.phase = "idle"
        return
    end

    local enemy_act = get_action_id(state.enemy_slot)
    if enemy_act > 0 and enemy_act ~= state.enemy_baseline_action_id then
        state.enemy_action_changed = true
    end
    local enemy_hp_now = read_player_hp(state.enemy_slot)
    if enemy_hp_now ~= nil then
        state.enemy_hp_after = enemy_hp_now
        if state.enemy_hp_min == nil or enemy_hp_now < state.enemy_hp_min then
            state.enemy_hp_min = enemy_hp_now
        end
        local hp_before = tonumber(state.enemy_hp_before)
        if hp_before and enemy_hp_now < (hp_before - 0.0001) then
            state.enemy_damage_seen = true
        end
    end

    if state.phase == "pre_approach" then
        local total_steps = 3 -- forward, pause, forward
        if state.pre_approach_step_index > total_steps then
            state.pre_approach_wait_left = math.max(0, tonumber(state.pre_approach_settle_frames) or 0)
            state.phase = "pre_approach_settle"
            return
        end

        if state.pre_approach_step_frames_left <= 0 then
            if state.pre_approach_step_index == 2 then
                state.pre_approach_step_frames_left = math.max(1, tonumber(state.pre_approach_pause_frames) or 1)
            else
                state.pre_approach_step_frames_left = math.max(1, tonumber(state.pre_approach_dir_frames) or 2)
            end

            local mask = 0
            if state.pre_approach_step_index ~= 2 then
                mask = get_forward_dir_mask()
            end

            state.pending_inject.slot = state.self_slot
            state.pending_inject.mask = mask
            if mask == 0 then
                state.pending_inject.frames_left = 0
            else
                state.pending_inject.frames_left = state.pre_approach_step_frames_left
            end
            state.step_wait_timeout = state.pre_approach_step_frames_left + 20
        end

        if state.pending_inject.frames_left <= 0 then
            state.pre_approach_step_frames_left = 0
            state.pre_approach_step_index = state.pre_approach_step_index + 1
        else
            state.step_wait_timeout = state.step_wait_timeout - 1
            if state.step_wait_timeout <= 0 then
                state.pre_approach_step_frames_left = 0
                state.pending_inject.mask = 0
                state.pending_inject.frames_left = 0
                state.pre_approach_step_index = state.pre_approach_step_index + 1
            end
        end
        return
    end

    if state.phase == "pre_approach_settle" then
        state.pre_approach_wait_left = state.pre_approach_wait_left - 1
        if state.pre_approach_wait_left <= 0 then
            state.phase = "input"
        end
        return
    end

    if state.phase == "input" then
        local cmd = get_active_cmd(move)
        if not cmd then
            finalize_current_move("invalid_command")
            return
        end
        local total_steps = get_total_steps(cmd)

        if state.step_index > total_steps then
            local root = move.command
            if root and root.execution_mode == "sequence"
                and type(root.sequence) == "table"
                and state.sequence_index < #root.sequence then
                state.sequence_index = state.sequence_index + 1
                state.step_index = 1
                state.step_frames_left = 0
                state.step_wait_timeout = 0
            else
                state.phase = "wait_start"
                state.startup_wait_left = state.startup_wait_frames
            end
            return
        end

        if state.step_frames_left <= 0 then
            state.step_frames_left = get_step_frames(cmd, state.step_index)
            state.step_wait_timeout = state.step_frames_left + 20

            local self_cp = get_cplayer(state.self_slot)
            local enemy_cp = get_cplayer(state.enemy_slot)
            local is_left = facing_is_left(self_cp, enemy_cp)
            local mask = build_step_mask(cmd, is_left, state.step_index)
            state.pending_inject.slot = state.self_slot
            state.pending_inject.mask = mask
            if mask == 0 then
                state.pending_inject.frames_left = 0
            else
                state.pending_inject.frames_left = state.step_frames_left
            end
        end

        if state.pending_inject.frames_left <= 0 then
            state.step_frames_left = 0
            state.step_index = state.step_index + 1
        else
            state.step_wait_timeout = state.step_wait_timeout - 1
            if state.step_wait_timeout <= 0 then
                state.last_status = "Input timeout: hook did not consume frame"
                finalize_current_move("input_timeout")
            end
        end
        return
    end

    if state.phase == "wait_start" then
        local act = get_action_id(state.self_slot)
        if act > 0 and act ~= state.baseline_action_id then
            state.observed_ids[act] = true
            state.phase = "wait_end"
            state.completion_wait_left = state.completion_wait_frames
            state.idle_confirm_left = state.idle_confirm_frames
            return
        end

        state.startup_wait_left = state.startup_wait_left - 1
        if state.startup_wait_left <= 0 then
            finalize_current_move("no_start")
        end
        return
    end

    if state.phase == "wait_end" then
        local act = get_action_id(state.self_slot)
        if act > 0 and act ~= state.baseline_action_id then
            state.observed_ids[act] = true
            state.idle_confirm_left = state.idle_confirm_frames
        else
            state.idle_confirm_left = state.idle_confirm_left - 1
            if state.idle_confirm_left <= 0 then
                finalize_current_move()
                return
            end
        end

        state.completion_wait_left = state.completion_wait_left - 1
        if state.completion_wait_left <= 0 then
            finalize_current_move("end_timeout")
        end
        return
    end
end

local function progress_text()
    if not state.loaded then
        return "No move list loaded"
    end
    return string.format("%d / %d", math.min(state.move_index, #state.run_moves), #state.run_moves)
end

local function current_move_text()
    if state.phase ~= "input" and state.phase ~= "wait_start" and state.phase ~= "wait_end" then
        return "-"
    end
    local move = state.current_move
    if not move then
        return "-"
    end
    return string.format("%s (%s)", tostring(move.move_name), tostring(move.num_cmd or ""))
end

re.on_frame(function()
    if not state.inject_hook_ready then
        install_inject_hooks()
    end

    local cid = get_chara_id(state.self_slot)
    if cid and cid > 0 then
        state.chara_id = cid
    end
    tick_runner()
end)

re.on_draw_ui(function()
    if not imgui.tree_node("SF6 Action Map Capture") then
        return
    end

    local slot_label = state.self_slot == 0 and "P1" or "P2"
    if imgui.button("Controlled Slot: " .. slot_label) then
        state.self_slot = 1 - state.self_slot
        state.enemy_slot = 1 - state.self_slot
        state.last_status = "Switched slot"
    end

    imgui.text(string.format("Self Chara ID: %s", tostring(state.chara_id)))
    imgui.text(string.format("Chara Dir: %s", tostring(state.chara_dir or "(auto by alias)")))
    imgui.text(string.format("Final Path: %s", tostring(state.final_path or "-")))

    if imgui.button("Load Moves From final.json") then
        local cid = get_chara_id(state.self_slot)
        if cid and cid > 0 then
            local ok, err = load_moves_for_character(cid)
            if not ok then
                state.last_status = "Load failed: " .. tostring(err)
            end
        else
            state.last_status = "Cannot detect self character id"
        end
    end

    imgui.same_line()
    if imgui.button("Reset Progress") then
        reset_runtime_progress()
        state.batch_active = false
        state.batch_run_remaining = 0
        state.batch_run_total = 0
        state.force_new_output_slot = false
        state.last_status = "Progress reset"
    end

    imgui.same_line()
    if imgui.button("Runs -") then
        state.batch_run_target = math.max(1, (tonumber(state.batch_run_target) or 5) - 1)
    end
    imgui.same_line()
    if imgui.button("Runs +") then
        state.batch_run_target = math.min(99, (tonumber(state.batch_run_target) or 5) + 1)
    end

    if imgui.button("Start Capture") then
        if not state.inject_hook_ready then
            state.last_status = "Start blocked: inject hook not ready - " .. tostring(state.inject_hook_error)
        elseif state.loaded and #state.run_moves > 0 then
            state.batch_run_target = math.max(1, tonumber(state.batch_run_target) or 5)
            state.batch_active = true
            state.batch_run_total = state.batch_run_target
            state.batch_run_remaining = state.batch_run_target
            state.force_new_output_slot = true
            reset_runtime_progress()
            state.running = true
            state.done = false
            if state.phase == "idle" and state.move_index < 1 then
                state.move_index = 1
            end
            state.last_status = string.format("Batch capture started: %d runs", state.batch_run_total)
        else
            state.last_status = "No runnable moves loaded"
        end
    end

    imgui.same_line()
    if imgui.button("Stop") then
        state.running = false
        state.batch_active = false
        state.batch_run_remaining = 0
        state.batch_run_total = 0
        state.force_new_output_slot = false
        state.last_status = "Capture stopped"
    end

    imgui.same_line()
    if imgui.button("Save Now") then
        save_results()
    end

    imgui.separator()
    imgui.text(string.format("Running: %s  Done: %s", tostring(state.running), tostring(state.done)))
    imgui.text(string.format(
        "Batch runs target=%d active=%s remaining=%d",
        tonumber(state.batch_run_target) or 5,
        tostring(state.batch_active),
        tonumber(state.batch_run_remaining) or 0
    ))
    imgui.text(string.format("Inject hook: %s", state.inject_hook_ready and "ready" or ("error: " .. tostring(state.inject_hook_error))))
    imgui.text("Capture context: auto")
    imgui.text("Last detected context: " .. tostring(state.last_detected_context or "unlabeled"))
    imgui.text(string.format("Pending inject: mask=0x%X remain=%d", state.pending_inject.mask or 0, state.pending_inject.frames_left or 0))
    imgui.text("Progress: " .. progress_text())
    imgui.text("Phase: " .. tostring(state.phase))
    imgui.text("Current Move: " .. current_move_text())
    imgui.text(string.format("Last Self ActionID: %d", state.last_self_action_id))
    imgui.text(string.format("Loaded runnable/skipped: %d / %d", #state.run_moves, #state.skipped_moves))

    if state.last_output_path ~= "" then
        imgui.text("Last Output: " .. state.last_output_path)
    end

    if state.inject_last_note ~= "" then
        if imgui.text_wrapped then
            imgui.text_wrapped(state.inject_last_note)
        else
            imgui.text(state.inject_last_note)
        end
    end

    if state.last_status ~= "" then
        if imgui.text_wrapped then
            imgui.text_wrapped(state.last_status)
        else
            imgui.text(state.last_status)
        end
    end

    imgui.tree_pop()
end)
