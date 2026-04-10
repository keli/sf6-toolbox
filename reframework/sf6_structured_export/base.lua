return function(ctx)
    local function normalize_path(path)
        return tostring(path or ""):gsub("\\", "/")
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
        local ok, result =
            pcall(compat_convert_to_json_tbl, value, max_layers, skip_arrays, skip_collections, skip_method_objs)
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
            local ok, enum_tbl = pcall(compat_get_enum, enum_name)
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
            local ok, enum_tbl = pcall(compat_get_enum, enum_name)
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

    ctx.normalize_path = normalize_path
    ctx.paths = {
        toolbox_root = TOOLBOX_ROOT,
        structured_base_dir = STRUCTURED_BASE_DIR,
        structured_char_dir = STRUCTURED_CHAR_DIR,
        config_path = CONFIG_PATH,
        index_path = INDEX_PATH,
        aliases_path = ALIASES_PATH,
    }
    ctx.state = state
    ctx.compat = {
        get_enum = compat_get_enum,
        lua_get_array = compat_lua_get_array,
        lua_get_dict = compat_lua_get_dict,
        convert_to_json_tbl = compat_convert_to_json_tbl,
    }
    ctx.checkbox_value = checkbox_value
    ctx.safe_imgui_text_wrapped = safe_imgui_text_wrapped
    ctx.load_json_or = load_json_or
    ctx.ensure_output_dirs = ensure_output_dirs
    ctx.safe_json_dump = safe_json_dump
    ctx.save_state = save_state
    ctx.save_aliases = save_aliases
    ctx.read_mvalue_number = read_mvalue_number
    ctx.safe_convert_to_json_tbl = safe_convert_to_json_tbl
    ctx.safe_get_elements = safe_get_elements
    ctx.to_iterable_table = to_iterable_table
    ctx.get_gbattle_type = get_gbattle_type
    ctx.get_battle_field_data = get_battle_field_data
    ctx.get_chara_name = get_chara_name
    ctx.get_alias_name = get_alias_name
    ctx.build_roster = build_roster
    ctx.read_motion_name = read_motion_name
    ctx.dedupe_sorted_numbers = dedupe_sorted_numbers
    ctx.count_entries = count_entries
    ctx.append_unique = append_unique
end
