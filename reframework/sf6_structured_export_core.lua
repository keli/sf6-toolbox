local source_path = debug.getinfo(1, "S").source:gsub("^@", "")
local base_dir = source_path:match("^(.*)[/\\][^/\\]+$") or "."
local modules_dir = base_dir .. "\\sf6_structured_export"

local function load_module(ctx, name)
    local path = modules_dir .. "\\" .. name .. ".lua"
    local loader = dofile(path)
    if type(loader) ~= "function" then
        error(string.format("module %s must return initializer function", name))
    end
    loader(ctx)
end

local ctx = {}
load_module(ctx, "base")
load_module(ctx, "export")
load_module(ctx, "ui")

ctx.build_roster()
ctx.save_aliases()
ctx.save_state()
