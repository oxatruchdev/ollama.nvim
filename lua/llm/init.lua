local Job = require("plenary.job")
local M = {}

local timeout_ms = 10000
local active_job = nil

local service_lookup = {
	groq = {
		url = "https://api.groq.com/openai/v1/chat/completions",
		model = "llama3-70b-8192",
		api_key_name = "GROQ_API_KEY",
	},
	openai = {
		url = "https://api.openai.com/v1/chat/completions",
		model = "gpt-4o",
		api_key_name = "OPENAI_API_KEY",
	},
	anthropic = {
		url = "https://api.anthropic.com/v1/messages",
		model = "claude-3-5-sonnet-20240620",
		api_key_name = "ANTHROPIC_API_KEY",
	},
	ollama = {
		url = "http://localhost:11434/api/chat",
		model = "llama3",
		api_key_name = nil, -- Ollama doesn't require an API key
	},
}

local function get_api_key(name)
	return os.getenv(name)
end

function M.setup(opts)
	timeout_ms = opts.timeout_ms or timeout_ms
	if opts.services then
		for key, service in pairs(opts.services) do
			service_lookup[key] = service
		end
	end
end

function M.get_lines_until_cursor()
	local current_buffer = vim.api.nvim_get_current_buf()
	local current_window = vim.api.nvim_get_current_win()
	local cursor_position = vim.api.nvim_win_get_cursor(current_window)
	local row = cursor_position[1]

	local lines = vim.api.nvim_buf_get_lines(current_buffer, 0, row, true)

	return table.concat(lines, "\n")
end

local function write_string_at_cursor(str)
	local current_window = vim.api.nvim_get_current_win()
	local cursor_position = vim.api.nvim_win_get_cursor(current_window)
	local row, col = cursor_position[1], cursor_position[2]

	local lines = vim.split(str, "\n")
	vim.api.nvim_put(lines, "c", true, true)

	local num_lines = #lines
	local last_line_length = #lines[num_lines]
	vim.api.nvim_win_set_cursor(current_window, { row + num_lines - 1, col + last_line_length })
end

local function process_data_lines(line, service, process_data)
	local data

	if service == "ollama" and line ~= nil then
		if line:match("%S") then -- Ensure line is not just whitespace
			local status, result = pcall(vim.json.decode, line)
			if status then
				data = result
			else
				print("JSON decode error:", result)
			end
		end
	else
		local data_start = line:find("data: ")
		if data_start then
			local json_str = line:sub(data_start + 6)
			if json_str == "[DONE]" then
				return true
			end
			local status, result = pcall(vim.json.decode, json_str)
			if status then
				data = result
			else
				print("JSON decode error:", result)
			end
		end
	end

	if data then
		local stop
		if service == "anthropic" then
			stop = data.type == "message_stop"
		elseif service == "ollama" then
			stop = data.done
		end

		if stop then
			return true
		else
			vim.schedule(function()
				vim.cmd("undojoin")
				process_data(data)
			end)
		end
	end
	return false
end

local function process_sse_response(lines, service)
	process_data_lines(lines, service, function(data)
		local content
		print("LINES:", lines)
		if service == "anthropic" then
			if data.delta and data.delta.text then
				content = data.delta.text
			end
		elseif service == "ollama" then
			if data.message and data.message.content then
				content = data.message.content
			end
		else
			if data.choices and data.choices[1] and data.choices[1].delta then
				content = data.choices[1].delta.content
			end
		end
		if content and content ~= vim.NIL then
			write_string_at_cursor(content)
		end
	end)
end

function M.prompt(opts)
	local replace = opts.replace
	local service = opts.service
	local prompt = ""
	local visual_lines = M.get_visual_selection()
	local system_prompt = opts.system_prompt
		or [[
You are an AI programming assistant integrated into a code editor. Your purpose is to help the user with programming tasks as they write code.
Key capabilities:
- Thoroughly analyze the user's code and provide insightful suggestions for improvements related to best practices, performance, readability, and maintainability. Explain your reasoning.
- Answer coding questions in detail, using examples from the user's own code when relevant. Break down complex topics step-by-step.
- Spot potential bugs and logical errors. Alert the user and suggest fixes.
- Upon request, add helpful comments explaining complex or unclear code.
- Suggest relevant documentation, StackOverflow answers, and other resources related to the user's code and questions.
- Engage in back-and-forth conversations to understand the user's intent and provide the most helpful information.
- Keep concise and use markdown.
- When asked to create code, only generate the code. No bugs.
- Think step by step
    ]]
	if visual_lines then
		prompt = table.concat(visual_lines, "\n")
		if replace then
			system_prompt =
				"You should replace the code that you are sent, only following the comments. Do not talk at all. Only output valid code. Do not provide any backticks that surround the code. Never ever output backticks like this ```. Any comment that is asking you for something should be removed after you satisfy them. Other comments should left alone. Do not output backticks"
			vim.api.nvim_command("normal! d")
			vim.api.nvim_command("normal! k")
		else
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", false, true, true), "nx", false)
		end
	else
		prompt = M.get_lines_until_cursor()
	end

	local url = ""
	local model = ""
	local api_key_name = ""

	local found_service = service_lookup[service]
	if found_service then
		url = found_service.url
		api_key_name = found_service.api_key_name
		model = found_service.model
	else
		print("Invalid service: " .. service)
		return
	end

	local api_key = api_key_name and get_api_key(api_key_name)

	local data
	if service == "anthropic" then
		data = {
			messages = {
				{
					role = "user",
					content = system_prompt .. "\n" .. prompt,
				},
			},
			model = model,
			stream = true,
			max_tokens = 1024,
		}
	elseif service == "ollama" then
		data = {
			model = opts.model and opts.model or model,
			messages = {
				{
					role = "system",
					content = system_prompt,
				},
				{
					role = "user",
					content = prompt,
				},
			},
			stream = true,
		}
	else
		data = {
			messages = {
				{
					role = "system",
					content = system_prompt,
				},
				{
					role = "user",
					content = prompt,
				},
			},
			model = model,
			temperature = 0.7,
			stream = true,
		}
	end

	local args = {
		"-N",
		"-X",
		"POST",
		"-H",
		"Content-Type: application/json",
		"-d",
		vim.json.encode(data),
	}

	if api_key and service ~= "ollama" then
		if service == "anthropic" then
			table.insert(args, "-H")
			table.insert(args, "x-api-key: " .. api_key)
			table.insert(args, "-H")
			table.insert(args, "anthropic-version: 2023-06-01")
		else
			table.insert(args, "-H")
			table.insert(args, "Authorization: Bearer " .. api_key)
		end
	end

	table.insert(args, url)

	if active_job then
		active_job:shutdown()
		active_job = nil
	end

	active_job = Job:new({
		command = "curl",
		args = args,
		on_stdout = function(_, out)
			process_sse_response(out, service)
		end,
		on_stderr = function(_, _) end,
		on_exit = function()
			active_job = nil
		end,
	})

	active_job:start()
	vim.api.nvim_command("normal! o")
end

function M.get_visual_selection()
	local _, srow, scol = unpack(vim.fn.getpos("v"))
	local _, erow, ecol = unpack(vim.fn.getpos("."))

	-- visual line mode
	if vim.fn.mode() == "V" then
		if srow > erow then
			return vim.api.nvim_buf_get_lines(0, erow - 1, srow, true)
		else
			return vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
		end
	end

	-- regular visual mode
	if vim.fn.mode() == "v" then
		if srow < erow or (srow == erow and scol <= ecol) then
			return vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
		else
			return vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {})
		end
	end

	-- visual block mode
	if vim.fn.mode() == "\22" then
		local lines = {}
		if srow > erow then
			srow, erow = erow, srow
		end
		if scol > ecol then
			scol, ecol = ecol, scol
		end
		for i = srow, erow do
			table.insert(
				lines,
				vim.api.nvim_buf_get_text(0, i - 1, math.min(scol - 1, ecol), i - 1, math.max(scol - 1, ecol), {})[1]
			)
		end
		return lines
	end
end

function M.create_llm_md()
	local cwd = vim.fn.getcwd()
	local cur_buf = vim.api.nvim_get_current_buf()
	local cur_buf_name = vim.api.nvim_buf_get_name(cur_buf)
	local llm_md_path = cwd .. "/llm.md"
	if cur_buf_name ~= llm_md_path then
		vim.api.nvim_command("edit " .. llm_md_path)
		local buf = vim.api.nvim_get_current_buf()
		vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
		vim.api.nvim_win_set_buf(0, buf)
	end
end

return M
