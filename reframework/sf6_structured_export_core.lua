local function normalize_path(path)
    return tostring(path or ""):gsub("\\", "/")
end

local function dirname(path)
    return normalize_path(path):match("^(.*)/[^/]+$")
end

local function get_script_dir()
    local src = ""
    local ok, info = pcall(debug.getinfo, 1, "S")
    if ok and info and type(info.source) == "string" then
        src = info.source
    end
    if src:sub(1, 1) == "@" then
        src = src:sub(2)
    end
    return dirname(src) or "."
end

local function resolve_toolbox_root()
    -- REFramework json/fs APIs are sandboxed under reframework/data.
    -- Keep all paths explicitly relative to that root.
    return "sf6-toolbox"
end

local TOOLBOX_ROOT = resolve_toolbox_root()

local STRUCTURED_BASE_DIR = TOOLBOX_ROOT .. "/structured"
local STRUCTURED_CHAR_DIR = STRUCTURED_BASE_DIR .. "/characters"
local CONFIG_PATH = STRUCTURED_BASE_DIR .. "/sf6_structured_export.json"
local INDEX_PATH = STRUCTURED_BASE_DIR .. "/sf6_structured_index.json"
local ALIASES_PATH = TOOLBOX_ROOT .. "/sf6_character_aliases.json"

local function compat_get_enum(typename)
    local enum, names, reverse_enum = {}, {}, {}
    local tdef = sdk.find_type_definition(typename)
    if not tdef then
        return { enum = enum, names = names, reverse_enum = reverse_enum }
    end
    for _, field in ipairs(tdef:get_fields()) do
        if field:is_static() then
            local ok, value = pcall(field.get_data, field)
            if ok and value ~= nil then
                local name = field:get_name()
                enum[name] = value
                reverse_enum[value] = name
                table.insert(names, name)
            end
        end
    end
    return { enum = enum, names = names, reverse_enum = reverse_enum }
end

local function compat_lua_get_array(src_obj, allow_empty)
    if not src_obj then
        return (allow_empty and {}) or nil
    end
    src_obj = src_obj._items or src_obj.mItems or src_obj
    local system_array
    if src_obj.get_Count then
        system_array = {}
        for i = 1, src_obj:call("get_Count") do
            system_array[i] = src_obj:get_Item(i - 1)
        end
    end
    if not system_array and src_obj.get_elements then
        system_array = src_obj:get_elements()
    end
    if allow_empty then
        return system_array or {}
    end
    return system_array and system_array[1] and system_array or nil
end

local function compat_lua_get_dict(dict, as_array, sort_fn)
    local output = {}
    if not dict or not dict._entries then
        return output
    end
    if as_array then
        for i, value_obj in pairs(dict._entries) do
            output[i] = value_obj.value
        end
        if sort_fn then
            table.sort(output, sort_fn)
        end
    else
        for _, value_obj in pairs(dict._entries) do
            if value_obj.value ~= nil then
                output[value_obj.key] = output[value_obj.key] or value_obj.value
            end
        end
    end
    return output
end

local function compat_convert_to_json_tbl(obj, max_layers, _skip_arrays, _skip_collections, _skip_method_objs)
    max_layers = max_layers or 6
    local visited = {}

    local function recurse(value, depth)
        if value == nil then
            return nil
        end
        local t = type(value)
        if t == "string" or t == "number" or t == "boolean" then
            return value
        end
        if depth > max_layers then
            return tostring(value)
        end
        if t == "table" then
            if visited[value] then
                return "<cycle>"
            end
            visited[value] = true
            local out = {}
            for k, v in pairs(value) do
                out[tostring(k)] = recurse(v, depth + 1)
            end
            return out
        end
        if t == "userdata" then
            if visited[value] then
                return "<cycle>"
            end
            visited[value] = true
            local td = value.get_type_definition and value:get_type_definition()
            if not td then
                return tostring(value)
            end
            local td_name = td:get_full_name()
            if td_name:find("via%.[Ss]fix") and value.ToFloat then
                local ok, num = pcall(value.ToFloat, value)
                if ok then
                    return num
                end
            end
            if td:is_a("System.Array") then
                local out = {}
                for i, elem in pairs(value) do
                    if elem == nil then
                        break
                    end
                    out[tostring(i)] = recurse(elem, depth + 1)
                end
                return out
            end
            local out = {}
            for _, field in ipairs(td:get_fields()) do
                if not field:is_static() then
                    local name = field:get_name()
                    if name:sub(1, 2) ~= "<>" and name ~= "_object" then
                        local ok, fdata = pcall(field.get_data, field, value)
                        if ok then
                            out[name] = recurse(fdata, depth + 1)
                        end
                    end
                end
            end
            if next(out) then
                return out
            end
            return tostring(value)
        end
        return tostring(value)
    end

    return recurse(obj, 0)
end

local convert_to_json_tbl = compat_convert_to_json_tbl
local get_enum = compat_get_enum
local lua_get_array = compat_lua_get_array
local lua_get_dict = compat_lua_get_dict

local state = {
    config = {
        include_raw_commands = true,
        include_raw_rects = true,
        include_raw_hit_data = true,
        include_raw_triggers = true,
        include_key_payloads = true,
    },
    db = {
        schema_version = 1,
        exporter = "sf6_structured_export",
        roster = {},
        characters = {},
    },
    aliases = {},
    exported_once = {},
    last_status = "",
}

local mot_info = sdk.create_instance("via.motion.MotionInfo"):add_ref()
log.info("[sf6_structured_export] core loaded")
log.info("[sf6_structured_export] data root: " .. tostring(STRUCTURED_BASE_DIR))

local function checkbox_value(label, current)
    local a, b = imgui.checkbox(label, current)
    if type(a) == "boolean" and type(b) == "boolean" then
        return a, b
    end
    if type(a) == "boolean" and b == nil then
        local new_value = a
        return new_value ~= current, new_value
    end
    return false, current
end

local imgui_wrapped_text_fn = nil
if imgui then
    if type(imgui.text_wrapped) == "function" then
        imgui_wrapped_text_fn = imgui.text_wrapped
    elseif type(imgui.text) == "function" then
        imgui_wrapped_text_fn = imgui.text
    end
end

local missing_imgui_text_warned = false
local function safe_imgui_text_wrapped(text)
    if imgui_wrapped_text_fn then
        imgui_wrapped_text_fn(text)
        return
    end

    if not missing_imgui_text_warned then
        missing_imgui_text_warned = true
        log.error("[sf6_structured_export] imgui text API missing; status text will be logged only")
    end

    log.info("[sf6_structured_export] " .. tostring(text))
end

local function load_json_or(default_value, path)
    local loaded = json.load_file(path)
    if loaded ~= nil then
        return loaded
    end
    return default_value
end

local function ensure_output_dirs()
    if fs and type(fs.create_directories) == "function" then
        pcall(fs.create_directories, STRUCTURED_BASE_DIR)
        pcall(fs.create_directories, STRUCTURED_CHAR_DIR)
        return
    end
    if fs and type(fs.create_directory) == "function" then
        pcall(fs.create_directory, STRUCTURED_BASE_DIR)
        pcall(fs.create_directory, STRUCTURED_CHAR_DIR)
    end
end

local function safe_json_dump(path, value)
    local ok, result = pcall(json.dump_file, path, value)
    if ok and result ~= false then
        return true
    end
    log.error("[sf6_structured_export] json.dump_file failed for " .. tostring(path) .. ": " .. tostring(result))
    return false
end

local function save_state()
    ensure_output_dirs()
    local ok_cfg = safe_json_dump(CONFIG_PATH, state.config)
    local ok_idx = safe_json_dump(INDEX_PATH, state.db)
    return ok_cfg and ok_idx
end

state.config = load_json_or(state.config, CONFIG_PATH)
state.db = load_json_or(state.db, INDEX_PATH)
state.aliases = load_json_or(state.aliases, ALIASES_PATH)
state.aliases = state.aliases or {}
if type(state.aliases.by_id) ~= "table" then
    state.aliases.by_id = {}
end
state.db.characters = state.db.characters or {}
state.db.roster = state.db.roster or {}

local function save_aliases()
    safe_json_dump(ALIASES_PATH, state.aliases)
end

local function read_mvalue_number(value)
    if type(value) == "number" then
        return value
    end
    if value ~= nil then
        local mv = value.mValue
        if type(mv) == "number" then
            return mv
        end
    end
    return nil
end

local function safe_convert_to_json_tbl(value, max_layers, skip_arrays, skip_collections, skip_method_objs)
    local ok, result = pcall(convert_to_json_tbl, value, max_layers, skip_arrays, skip_collections, skip_method_objs)
    if ok then
        return result
    end
    log.error("[sf6_structured_export] convert_to_json_tbl failed: " .. tostring(result))
    return { __error = tostring(result), __value = tostring(value) }
end

local function safe_get_elements(obj)
    if not obj or type(obj.get_elements) ~= "function" then
        return nil
    end
    local ok, elements = pcall(obj.get_elements, obj)
    if ok then
        return elements
    end
    log.error("[sf6_structured_export] get_elements failed: " .. tostring(elements))
    return nil
end

local function to_iterable_table(value, prefer_zero_based)
    if type(value) == "table" then
        return value
    end
    if value == nil then
        return {}
    end

    if value._items ~= nil then
        return to_iterable_table(value._items, prefer_zero_based)
    end
    if value.mItems ~= nil then
        return to_iterable_table(value.mItems, prefer_zero_based)
    end

    local elements = safe_get_elements(value)
    if type(elements) == "table" then
        return elements
    end

    if type(value.get_Count) == "function" and type(value.get_Item) == "function" then
        local ok_count, count = pcall(value.call, value, "get_Count")
        if ok_count and type(count) == "number" and count >= 0 then
            local out = {}
            for i = 0, count - 1 do
                local ok_item, item = pcall(value.get_Item, value, i)
                if ok_item then
                    out[prefer_zero_based and i or (i + 1)] = item
                end
            end
            return out
        end
    end

    return {}
end

local function get_gbattle_type()
    return sdk.find_type_definition("gBattle")
end

local function get_battle_field_data(field_name)
    local gBattle = get_gbattle_type()
    if not gBattle then
        return nil
    end
    local field = gBattle:get_field(field_name)
    return field and field:get_data()
end

local function get_chara_name(chara_id)
    local enum_names = {
        "nBattle.CHARA_ID",
        "app.battle.PlayerType",
        "app.CharacterID",
    }
    for _, enum_name in ipairs(enum_names) do
        local ok, enum_tbl = pcall(get_enum, enum_name)
        if ok and enum_tbl and enum_tbl.reverse_enum and enum_tbl.reverse_enum[chara_id] then
            return enum_tbl.reverse_enum[chara_id]
        end
    end
    return string.format("chara_%03d", chara_id)
end

local function get_alias_name(chara_id, enum_name)
    local by_id = state.aliases.by_id or {}
    local alias = by_id[tostring(chara_id)] or by_id[string.format("%03d", chara_id)]
    if alias and alias ~= "" then
        return alias
    end
    return enum_name
end

local function build_roster()
    local roster = {}
    local enum_candidates = {
        "app.CHARA_ID",
        "app::CHARA_ID",
        "nBattle.CHARA_ID",
    }

    for _, enum_name in ipairs(enum_candidates) do
        local ok, enum_tbl = pcall(get_enum, enum_name)
        if ok and enum_tbl and enum_tbl.enum then
            for name, value in pairs(enum_tbl.enum) do
                if type(value) == "number" and value >= 0 and name:match("^PL_%d%d%d$") then
                    local key = string.format("%03d", value)
                    roster[key] = {
                        chara_id = value,
                        enum_name = name,
                        display_name = get_alias_name(value, name),
                    }
                end
            end
        end
        if next(roster) then
            break
        end
    end

    state.db.roster = roster
    return roster
end

local function read_motion_name(motion, motion_type, motion_id)
    if not motion then
        return nil
    end
    local ok = pcall(
        motion.call,
        motion,
        "getMotionInfo(System.UInt32, System.UInt32, via.motion.MotionInfo)",
        motion_type,
        motion_id,
        mot_info
    )
    if not ok then
        return nil
    end
    local ok_name, motion_name = pcall(mot_info.get_MotionName, mot_info)
    if ok_name and motion_name and motion_name ~= "" then
        return motion_name
    end
    return nil
end

local function dedupe_sorted_numbers(values)
    local seen = {}
    local out = {}
    for _, value in ipairs(values or {}) do
        if type(value) == "number" and not seen[value] then
            seen[value] = true
            table.insert(out, value)
        end
    end
    table.sort(out)
    return out
end

local function count_entries(tbl)
    local count = 0
    for _, _ in pairs(tbl or {}) do
        count = count + 1
    end
    return count
end

local function collect_rects(person)
    local rects = {}
    if not person or not person.Rect or not person.Rect.RectList then
        return rects
    end
    for list_idx, dict in pairs(person.Rect.RectList) do
        rects[list_idx] = {}
        for rect_id, rect in pairs(lua_get_dict(dict)) do
            rects[list_idx][rect_id] = safe_convert_to_json_tbl(rect)
        end
    end
    return rects
end

local function collect_hit_datas(hit_datas)
    if not hit_datas then
        return {}
    end
    return safe_convert_to_json_tbl(lua_get_dict(hit_datas), nil, nil, nil, true) or {}
end

local function collect_triggers(user_engine)
    local triggers = {}
    local triggers_by_act_id = {}
    if not user_engine then
        return triggers, triggers_by_act_id
    end

    local ok_raw, raw_triggers = pcall(user_engine.call, user_engine, "GetTrigger()")
    if not ok_raw then
        log.error("[sf6_structured_export] GetTrigger() failed: " .. tostring(raw_triggers))
        return triggers, triggers_by_act_id
    end
    for trigger_idx, trigger in pairs(to_iterable_table(raw_triggers, true)) do
        if trigger then
            local json_trigger = safe_convert_to_json_tbl(trigger)
            triggers[trigger_idx] = json_trigger
            local action_id = json_trigger.action_id
            if type(action_id) == "number" then
                triggers_by_act_id[action_id] = triggers_by_act_id[action_id] or {}
                triggers_by_act_id[action_id][trigger_idx] = json_trigger
            end
        end
    end
    return triggers, triggers_by_act_id
end

local function append_unique(target, value)
    if value == nil then
        return
    end
    for _, existing in ipairs(target) do
        if existing == value then
            return
        end
    end
    table.insert(target, value)
end

local function collect_action_summary(player_ctx, style_id, fab_action)
    local action_id = fab_action.ActionID
    local act_enum = player_ctx.act_id_enum.reverse_enum[action_id]
    local action = {
        action_id = action_id,
        style_id = style_id,
        enum_name = act_enum,
        name = act_enum or string.format("_%03d", action_id),
        action_frame = safe_convert_to_json_tbl(fab_action.ActionFrame),
        projectile_data_index = fab_action.Projectile and fab_action.Projectile.DataIndex or nil,
        keys = {},
        attack_data_indices = {},
        hit_rect_refs = {},
        hurt_rect_refs = {},
        proximity_rect_refs = {},
        branch_action_ids = {},
        projectile_action_ids = {},
        trigger_group_ids = {},
        motion_entries = {},
        trigger_ids = {},
    }

    for list_idx, keys_list in pairs(lua_get_array(fab_action.Keys)) do
        if keys_list and keys_list._items and keys_list._items[0] then
            local keytype_name = keys_list._items[0]:get_type_definition():get_name()
            local out_group = {
                list_index = list_idx - 1,
                keys = {},
            }

            for key_idx, key in pairs(lua_get_array(keys_list, true)) do
                local key_payload = state.config.include_key_payloads and safe_convert_to_json_tbl(key) or {}
                local key_json = type(key_payload) == "table" and key_payload or { value = key_payload }
                key_json.index = key_idx
                out_group.keys[key_idx] = key_json

                if keytype_name == "AttackCollisionKey"
                    or keytype_name == "OtherCollisionKey"
                    or keytype_name == "GimmickCollisionKey"
                then
                    if key.AttackDataListIndex and key.AttackDataListIndex > -1 then
                        append_unique(action.attack_data_indices, key.AttackDataListIndex)
                    end
                    if key.BoxList then
                        local refs = {}
                        for _, box_id in pairs(key.BoxList) do
                            append_unique(refs, read_mvalue_number(box_id))
                        end
                        if #refs > 0 then
                            action.hit_rect_refs[key_idx] = {
                                collision_type = key.CollisionType or key.Kind,
                                rect_ids = dedupe_sorted_numbers(refs),
                            }
                        end
                    end
                    if key.CollisionType == 3 and key.BoxList then
                        local refs = {}
                        for _, box_id in pairs(key.BoxList) do
                            append_unique(refs, read_mvalue_number(box_id))
                        end
                        if #refs > 0 then
                            action.proximity_rect_refs[key_idx] = dedupe_sorted_numbers(refs)
                        end
                    end
                elseif keytype_name == "DamageCollisionKey" then
                    local hurt = {}
                    for _, list_name in ipairs({ "HeadList", "BodyList", "LegList", "ThrowList" }) do
                        local list = key[list_name]
                        if list and list.get_elements then
                            local ids = {}
                            for _, box_id in pairs(lua_get_array(list, true) or {}) do
                                append_unique(ids, read_mvalue_number(box_id))
                            end
                            if #ids > 0 then
                                hurt[list_name] = dedupe_sorted_numbers(ids)
                            end
                        end
                    end
                    if next(hurt) then
                        action.hurt_rect_refs[key_idx] = hurt
                    end
                elseif keytype_name == "ShotKey" then
                    append_unique(action.projectile_action_ids, key.ActionId)
                elseif keytype_name == "BranchKey" then
                    append_unique(action.branch_action_ids, key.Action)
                elseif keytype_name == "TriggerKey" then
                    append_unique(action.trigger_group_ids, key.TriggerGroup)
                elseif keytype_name == "LockKey" and key.Param02 and key.Param02 > -1 then
                    append_unique(action.attack_data_indices, key.Param02)
                end

                if keytype_name == "MotionKey"
                    or keytype_name == "ExtMotionKey"
                    or keytype_name == "FacialKey"
                    or keytype_name == "FacialAutoKey"
                then
                    local motion_source = keytype_name:find("Facial") and player_ctx.face_motion or player_ctx.motion
                    local motion_name = read_motion_name(motion_source, key.MotionType, key.MotionID)
                    local entry = {
                        motion_type = key.MotionType,
                        motion_id = key.MotionID,
                        motion_name = motion_name,
                        key_type = keytype_name,
                    }
                    table.insert(action.motion_entries, entry)
                    if keytype_name == "MotionKey" and motion_name and motion_name ~= "" then
                        action.name = motion_name:gsub("esf0%d%d_", "")
                    end
                end
            end

            action.keys[keytype_name] = out_group
        end
    end

    action.attack_data_indices = dedupe_sorted_numbers(action.attack_data_indices)
    action.branch_action_ids = dedupe_sorted_numbers(action.branch_action_ids)
    action.projectile_action_ids = dedupe_sorted_numbers(action.projectile_action_ids)
    action.trigger_group_ids = dedupe_sorted_numbers(action.trigger_group_ids)

    local trigger_rows = player_ctx.triggers_by_act_id[action_id]
    if trigger_rows then
        for trigger_idx, _ in pairs(trigger_rows) do
            table.insert(action.trigger_ids, trigger_idx)
        end
        table.sort(action.trigger_ids)
    end

    return action
end

local function collect_commands(command_resource)
    if not command_resource then
        return {}
    end
    local output = {}
    for command_list_id, command_list in pairs(lua_get_dict(command_resource.pCommand)) do
        output[command_list_id] = safe_convert_to_json_tbl(command_list)
    end
    return output
end

local function collect_trigger_groups(command_resource, triggers)
    if not command_resource then
        return {}
    end
    local output = {}
    for group_id, trigger_group in pairs(lua_get_dict(command_resource.pTrgGrp)) do
        local rows = {
            raw = safe_convert_to_json_tbl(trigger_group),
            trigger_ids = {},
        }
        local bitarray = trigger_group.Flag and trigger_group.Flag:BitArray()
        local retries = 0
        while bitarray and not bitarray.get_elements and retries < 8 do
            bitarray = trigger_group.Flag:BitArray()
            retries = retries + 1
        end
        local elements = safe_get_elements(bitarray)
        if elements then
            for _, entry in pairs(elements) do
                local trigger_id = read_mvalue_number(entry)
                if type(trigger_id) == "number" then
                    table.insert(rows.trigger_ids, trigger_id)
                end
            end
            table.sort(rows.trigger_ids)
        end
        rows.actions = {}
        for _, trigger_id in ipairs(rows.trigger_ids) do
            local trig = triggers[trigger_id]
            if trig and type(trig.action_id) == "number" then
                table.insert(rows.actions, trig.action_id)
            end
        end
        rows.actions = dedupe_sorted_numbers(rows.actions)
        output[group_id] = rows
    end
    return output
end

local function collect_player_export(player_index)
    local gBattle = get_gbattle_type()
    if not gBattle then
        return nil, "gBattle type unavailable"
    end
    local gPlayer = get_battle_field_data("Player")
    local gResource = get_battle_field_data("Resource")
    local gCommand = get_battle_field_data("Command")
    local pb_manager = gBattle:get_field("PBManager"):get_data()
    if not gPlayer or not gResource or not gCommand or not pb_manager then
        return nil, "battle handles unavailable"
    end

    local chara_id_obj = gPlayer.mPlayerType[player_index]
    local chara_id = read_mvalue_number(chara_id_obj)
    if type(chara_id) ~= "number" then
        return nil, "character id unavailable"
    end

    local player_obj = gPlayer.mcPlayer[player_index]
    local person = gResource.Data[player_index]
    local pb = pb_manager.Players[player_index]
    if not player_obj or not person or not pb or not person.FAB then
        return nil, "player resources unavailable"
    end

    local user_engine = gCommand:get_mUserEngine()[player_index]
    local triggers, triggers_by_act_id = collect_triggers(user_engine)
    local player_ctx = {
        act_id_enum = get_enum("nBattle.ACT_ID"),
        motion = pb.mpMot,
        face_motion = pb.mpFace,
        triggers_by_act_id = triggers_by_act_id,
    }

    local actions = {}
    local style_count = person.FAB.StyleDict and person.FAB.StyleDict:call("get_Count()") or 0
    for style_id = 0, style_count - 1 do
        local style = person.FAB.StyleDict[style_id]
        if style and style.ActionList then
            local act_list = lua_get_dict(style.ActionList, true, function(a, b)
                return a.ActionID < b.ActionID
            end)
            for _, fab_action in ipairs(act_list) do
                local action = collect_action_summary(player_ctx, style_id, fab_action)
                actions[string.format("%04d", action.action_id)] = action
            end
        end
    end

    local chara_name = get_chara_name(chara_id)
    local export = {
        schema_version = 1,
        chara_id = chara_id,
        chara_name = get_alias_name(chara_id, chara_name),
        enum_name = chara_name,
        player_slot = player_index + 1,
        generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        actions = actions,
        trigger_groups = collect_trigger_groups(gCommand.mpBCMResource[player_index], triggers),
    }

    if state.config.include_raw_commands then
        export.commands = collect_commands(gCommand.mpBCMResource[player_index])
    end
    if state.config.include_raw_rects then
        export.rects = collect_rects(person)
    end
    if state.config.include_raw_hit_data then
        export.hit_data = collect_hit_datas(gPlayer.mpLoadHitDataAddress[player_index])
    end
    if state.config.include_raw_triggers then
        export.triggers = triggers
    end

    return export, nil
end

local function write_character_export(export)
    ensure_output_dirs()
    local key = string.format("%03d", export.chara_id)
    state.db.roster[key] = state.db.roster[key] or {
        chara_id = export.chara_id,
        enum_name = export.enum_name,
        display_name = export.chara_name,
    }
    state.db.roster[key].last_exported_at = export.generated_at
    state.db.roster[key].action_count = count_entries(export.actions)
    state.db.characters[key] = export
    state.db.last_generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local export_path = string.format("%s/sf6_structured_%s.json", STRUCTURED_CHAR_DIR, key)
    local wrote_export = safe_json_dump(export_path, export)
    local wrote_state = save_state()
    if not wrote_export or not wrote_state then
        error("failed to write export files")
    end
    state.last_status = string.format(
        "Exported %s (%s) with %d actions",
        export.chara_name,
        key,
        count_entries(export.actions)
    )
end

build_roster()
save_aliases()
save_state()

local function export_player_slot(player_index)
    local ok, export_or_err, maybe_err = pcall(collect_player_export, player_index)
    if not ok then
        local err = tostring(export_or_err)
        state.last_status = string.format("P%d export crashed: %s", player_index + 1, err)
        log.error("[sf6_structured_export] export_player_slot failed: " .. err)
        return false
    end

    local export, err = export_or_err, maybe_err
    if not export then
        state.last_status = string.format("P%d export failed: %s", player_index + 1, err or "unknown error")
        return false
    end

    local ok_write, write_err = pcall(write_character_export, export)
    if not ok_write then
        state.last_status = string.format("P%d write failed: %s", player_index + 1, tostring(write_err))
        log.error("[sf6_structured_export] write_character_export failed: " .. tostring(write_err))
        return false
    end

    state.exported_once[export.chara_id] = true
    return true
end

re.on_draw_ui(function()
    local ok, err = pcall(function()
        if imgui.tree_node("SF6 Structured Export") then
            local changed = false
            changed, state.config.include_raw_commands =
                checkbox_value("Include raw commands", state.config.include_raw_commands)
            if changed then
                save_state()
            end

            changed, state.config.include_raw_rects =
                checkbox_value("Include raw rects", state.config.include_raw_rects)
            if changed then
                save_state()
            end

            changed, state.config.include_raw_hit_data =
                checkbox_value("Include raw hit data", state.config.include_raw_hit_data)
            if changed then
                save_state()
            end

            changed, state.config.include_raw_triggers =
                checkbox_value("Include raw triggers", state.config.include_raw_triggers)
            if changed then
                save_state()
            end

            changed, state.config.include_key_payloads =
                checkbox_value("Include key payloads", state.config.include_key_payloads)
            if changed then
                save_state()
            end

            if imgui.button("Export P1") then
                export_player_slot(0)
            end
            imgui.same_line()
            if imgui.button("Export P2") then
                export_player_slot(1)
            end
            imgui.same_line()
            if imgui.button("Refresh Roster") then
                build_roster()
                save_state()
                state.last_status = string.format("Roster refreshed: %d known ids", count_entries(state.db.roster))
            end

            if state.last_status ~= "" then
                safe_imgui_text_wrapped(state.last_status)
            end

            imgui.tree_pop()
        end
    end)
    if not ok then
        log.error("[sf6_structured_export] UI error: " .. tostring(err))
    end
end)
