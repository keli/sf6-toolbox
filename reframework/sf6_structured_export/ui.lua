return function(ctx)
    local state = ctx.state
    local checkbox_value = ctx.checkbox_value
    local safe_imgui_text_wrapped = ctx.safe_imgui_text_wrapped
    local save_state = ctx.save_state
    local build_roster = ctx.build_roster
    local count_entries = ctx.count_entries
    local export_player_slot = ctx.export_player_slot

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
end
