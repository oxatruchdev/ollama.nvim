# llm.nvim

A neovim plugin for no frills LLM-assisted programming.

https://github.com/osmodiar16/llm.nvim/assets/26916007/40691fdb-e2a3-473a-aace-ae7010a17a1d

### Motivation

I decided to make this plugin compatible with ollama since it's the easiest way - at least for me - to launch a LLM API and I like to keep things local.
The hard work has been done by [melbaldove](https://github.com/melbaldove) and [yacine](https://twitter.com/yacine).

### Installation

Before using the plugin, set any of `GROQ_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` env vars with your api keys.

This plugin also allows you to use a local Ollama server, which enables you to bypass the need for an API key.

lazy.nvim

```lua
{
    "osmodiar16/llm.nvim",
    dependencies = { 'nvim-lua/plenary.nvim' }
}
```

### Usage

**`setup()`**

Configure the plugin. This can be omitted to use the default configuration.

```lua
require('llm').setup({
    -- How long to wait for the request to start returning data.
    timeout_ms = 10000,
    services = {
        -- Supported services configured by default
        -- groq = {
        --     url = "https://api.groq.com/openai/v1/chat/completions",
        --     model = "llama3-70b-8192",
        --     api_key_name = "GROQ_API_KEY",
        -- },
        -- openai = {
        --     url = "https://api.openai.com/v1/chat/completions",
        --     model = "gpt-4o",
        --     api_key_name = "OPENAI_API_KEY",
        -- },
        -- anthropic = {
        --     url = "https://api.anthropic.com/v1/messages",
        --     model = "claude-3-5-sonnet-20240620",
        --     api_key_name = "ANTHROPIC_API_KEY",
        -- },

        -- Extra OpenAI-compatible services to add (optional)
        other_provider = {
            url = "https://example.com/other-provider/v1/chat/completions",
            model = "llama3",
            api_key_name = "OTHER_PROVIDER_API_KEY",
        }
    },
})
```

**`prompt()`**

Triggers the LLM assistant. You can pass an optional `replace` flag to replace the current selection with the LLM's response. The prompt is either the visually selected text or the file content up to the cursor if no selection is made.

**`create_llm_md()`**

Creates a new `llm.md` file in the current working directory, where you can write questions or prompts for the LLM.

**Example Bindings**

Default prompt

```lua
[[
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

```

````lua
vim.keymap.set("n", "<leader>m", function()
  require("llm").create_llm_md()
end)

-- keybinds for prompting with groq
vim.keymap.set("n", "<leader>,", function() require("llm").prompt({ replace = false, service = "groq" }) end)
vim.keymap.set("v", "<leader>,", function() require("llm").prompt({ replace = false, service = "groq" }) end)
vim.keymap.set("v", "<leader>.", function() require("llm").prompt({ replace = true, service = "groq" }) end)


//Examles of different prompts to send
local help_prompt = "You are a helpful assistant. What I have sent are my notes so far. You are very curt, yet helpful."

local replace_prompt = 'You should replace the code that you are sent, only following the comments. Do not talk at all. Only output valid code. Do not provide any backticks that surround the code. Never ever output backticks like this ```. Any comment that is asking you for something should be removed after you satisfy them. Other comments should left alone. Do not output backticks'

-- keybinds for prompting with ollama
vim.keymap.set("n", "<leader>g,", function()
  require("llm").prompt({ replace = false, service = "ollama", model = "llama3", prompt = help_prompt })
end)
vim.keymap.set("v", "<leader>g,", function()
  require("llm").prompt({ replace = false, service = "ollama", model = "llama3",  prompt = help_prompt })
end)
vim.keymap.set("v", "<leader>g.", function()
  require("llm").prompt({ replace = true, service = "ollama", model = "llama3", prompt = replace_prompt })
end)
````

## Roadmap

- Add a way to stop the generation even if it's not done

### Credits

- Special thanks to [yacine](https://twitter.com/i/broadcasts/1kvJpvRPjNaKE) and his ask.md vscode plugin for inspiration!
- Also special thanks to [melbaldove](https://github.com/melbaldove) for his [llm.nvim](https://github.com/melbaldove/llm.nvim) plugin which was the base to make this plugin compatible with ollama
