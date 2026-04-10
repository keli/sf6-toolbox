return function(ctx)
    local state = ctx.state
    local lua_get_array = ctx.compat.lua_get_array
    local lua_get_dict = ctx.compat.lua_get_dict
    local get_enum = ctx.compat.get_enum
    local safe_convert_to_json_tbl = ctx.safe_convert_to_json_tbl
    local safe_get_elements = ctx.safe_get_elements
    local to_iterable_table = ctx.to_iterable_table
    local read_mvalue_number = ctx.read_mvalue_number
    local get_battle_field_data = ctx.get_battle_field_data
    local get_gbattle_type = ctx.get_gbattle_type
    local get_chara_name = ctx.get_chara_name
    local get_alias_name = ctx.get_alias_name
    local read_motion_name = ctx.read_motion_name
    local dedupe_sorted_numbers = ctx.dedupe_sorted_numbers
    local count_entries = ctx.count_entries
    local append_unique = ctx.append_unique
    local ensure_output_dirs = ctx.ensure_output_dirs
    local safe_json_dump = ctx.safe_json_dump
    local save_state = ctx.save_state

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
        local export_path = string.format("%s/sf6_structured_%s.json", ctx.paths.structured_char_dir, key)
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

    ctx.collect_player_export = collect_player_export
    ctx.export_player_slot = export_player_slot
end
