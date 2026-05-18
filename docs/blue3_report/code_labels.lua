-- local function latex_escape(str)
--   str = str:gsub("\\", "\\textbackslash{}")
--   str = str:gsub("([%%_%$#&{}])", "\\%1")
--   str = str:gsub("%^", "\\textasciicircum{}")
--   str = str:gsub("~", "\\textasciitilde{}")
--   return str
-- end
--
-- function CodeBlock(block)
--   local filename = block.attributes["filename"]
--     or block.attributes["label"]
--     or block.attributes["title"]
--
--   if filename == nil then
--     return block
--   end
--
--   local safe_filename = latex_escape(filename)
--
--   return {
--     pandoc.RawBlock(
--       "latex",
--       "\\noindent\\fbox{\\texttt{" .. safe_filename .. "}}\\par\\vspace{-0.4em}"
--     ),
--     block
--   }
-- end

local base_url = "https://github.com/bathan1/caprice-lang/blob/main/src/"

local function latex_escape(str)
  str = str:gsub("\\", "\\textbackslash{}")
  str = str:gsub("([%%_%$#&{}])", "\\%1")
  str = str:gsub("%^", "\\textasciicircum{}")
  str = str:gsub("~", "\\textasciitilde{}")
  return str
end

local function url_escape(str)
  str = str:gsub(" ", "%%20")
  str = str:gsub("#", "%%23")
  return str
end

function CodeBlock(block)
  local filename = block.attributes["filename"]
    or block.attributes["label"]
    or block.attributes["title"]

  if filename == nil then
    return block
  end

  local safe_filename = latex_escape(filename)
  local url = base_url .. url_escape(filename)

  local latex =
    "\\noindent" ..
    "\\fbox{" ..
      "\\href{" .. url .. "}{" ..
        "\\textcolor{blue}{\\underline{\\texttt{" .. safe_filename .. "}}}" ..
      "}" ..
    "}" ..
    "\\par\\vspace{-0.4em}"

  return {
    pandoc.RawBlock("latex", latex),
    block
  }
end
