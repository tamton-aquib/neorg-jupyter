require("neorg.modules.base")

---@diagnostic disable-next-line: undefined-global
local module = neorg.modules.create("external.jupyter")
local ts = require("nvim-treesitter.ts_utils")

module.setup = function()
    return {
        success = true,
        requires = { "core.neorgcmd", "core.integrations.treesitter" }
    }
end

module.load = function()
    module.required["core.neorgcmd"].add_commands_from_table({
        jupyter = {
            args = 1,
            subcommands = {
                run = { args=0, name="jupyter.run" },
                hide = { args=0, name="jupyter.hide" },
                materialize = { args=0, name="jupyter.materialize" },
                init = { args=0, name="jupyter.init" },
                generate = { args=1, name="jupyter.generate" },
            }
        }
    })
end

module.private = {
    cursor = 1,
    cells = {},
    cell_counter = 1,
    ns = vim.api.nvim_create_namespace("jupyter_norgbook"),

    refresh = function()
        local c = module.private.cells[module.private.current]

        vim.api.nvim_buf_set_extmark(0, module.private.ns, c["end"], 0, {
            id = module.private.current,
            virt_lines = c.output
        })
    end,

    handle_line = function(_, data)
        for _, line in ipairs(data) do

            -- Cleaning the lines
            if line:match("In %[1%]:") then vim.notify("Kernel started!") end

            line = line
                :gsub("In %[%d*%]: ", ""):gsub("Out%[%d*%]: ", "")
                :gsub("%.%.%.: ", "")
                :gsub("^%s*", ""):gsub("%s*$", "")

            if line ~= "" then
                local current = module.private.cells[module.private.current]

                if current then
                    table.insert(
                        module.private.cells[module.private.current].output,
                        {{line, "Identifier"}}
                    )
                    module.private.refresh()
                end
            end
        end
    end,

    init = function()
        if module.private.jobid then
            vim.notify("Restarting the kernel!")
            vim.fn.jobstop(module.private.jobid)
        else
            vim.notify("Starting the kernel!")
        end

        module.private.jobid = vim.fn.jobstart("ipython", {
            width = vim.o.columns,
            on_stdout = module.private.handle_line,

            -- Probably redundant
            on_exit = function() vim.notify("Kernel shut down!") end
        })
    end,

    generate = function(file)
        local result = ""
        local f = io.open(vim.fn.expand(file), "r")

        if f ~= nil then
            local content = f:read "*a"
            local cells = vim.json.decode(content).cells
            for _, cell in ipairs(cells) do
                -- TODO: outputs too maybe.
                if cell.cell_type == "markdown" then
                    result = result .. table.concat(cell.source)
                elseif cell.cell_type == "code" then
                    result = result .. "\n@code python\n"
                    result = result .. table.concat(cell.source)..'\n'
                    result = result .. "@end\n\n"
                end
            end
        else
            print("Error reading file")
        end

        vim.api.nvim_put(vim.split(result, '\n'), "", false, false)
    end
}

module.public = {
    current_node_details = function()
        local node = ts.get_node_at_cursor(0, true)
        local p = module.required["core.integrations.treesitter"].find_parent(node, "^ranged_verbatim_tag$")
        local code_block = module.required["core.integrations.treesitter"].get_tag_info(p, true)

        local found_id
        for kid, kidc in pairs(module.private.cells) do
            if kidc.start == code_block["start"].row or kidc["end"] == code_block["end"].row then
                found_id = kid
                break
            end
        end

        return found_id, code_block
    end,

    hide = function()
        local found_id, _ = module.public.current_node_details()
        if found_id then
            vim.api.nvim_buf_del_extmark(0, module.private.ns, found_id)
        end
    end,

    materialize = function()
        local found_id, _ = module.public.current_node_details()

        if found_id then
            local c = module.private.cells[found_id]
            vim.api.nvim_buf_del_extmark(0, module.private.ns, found_id)

            local lines = vim.tbl_map(function(line) return vim.tbl_map(function(j) return j[1] end, line)[1] end, c.output)
            local count = 1
            vim.api.nvim_buf_set_lines(0, c["end"]+count, c["end"]+count, false, {"@output"})
            for i=1,#lines do
                vim.api.nvim_buf_set_lines(0, c["end"]+i+1, c["end"]+i+1, false, {lines[i]})
            end
            count = count + #lines
            vim.api.nvim_buf_set_lines(0, c["end"]+count+1, c["end"]+count+1, false, {"@end"})
        end
    end,

    run = function()
        if not module.private.jobid then
            vim.notify("Kernel not initiated!\nRun `:Neorg jupyter init` to start the kernel.")
            return
        end

        local found_id, code_block = module.public.current_node_details()
        local id = found_id or vim.api.nvim_buf_set_extmark(0, module.private.ns, code_block["start"].row, 0, {})

        module.private.cells[id] = {
            id = id,
            start = code_block["start"].row,
            ["end"] = code_block["end"].row,
            output = {}
        }

        vim.api.nvim_chan_send(module.private.jobid, table.concat(code_block["content"], '\n').."\n")
        module.private.current = id
    end
}

module.on_event = function(event)
    if event.split_type[2] == "jupyter.run" then
        vim.schedule(module.public.run)
    elseif event.split_type[2] == "jupyter.hide" then
        vim.schedule(module.public.hide)
    elseif event.split_type[2] == "jupyter.materialize" then
        vim.schedule(module.public.materialize)
    elseif event.split_type[2] == "jupyter.init" then
        vim.schedule(module.private.init)
    elseif event.split_type[2] == "jupyter.generate" then
        vim.schedule(function() module.private.generate(event.content[1]) end)
    end
end

module.events.subscribed = {
    ["core.neorgcmd"] = {
        ["jupyter.run"] = true,
        ["jupyter.hide"] = true,
        ["jupyter.materialize"] = true,
        ["jupyter.init"] = true,
        ["jupyter.generate"] = true
    }
}

return module
