#!/usr/bin/env lua5.2

local posix = require 'posix'
local url = require 'socket.url'
local xml = require 'pl.xml'
-- compatibility with Lua 5.1/LuaJIT
if _VERSION == "Lua 5.1" then
  table.unpack = unpack
end

local M = xml.new("openbox_pipe_menu")

local function swap(a, b)
  return b, a
end

local function quote(s)
  return string.format("%q", s)
end

local function printf(f, ...)
  print(string.format(f, ...))
end

local function decode_url(s)
  local s = s
  if s:sub(1, 1) == '_' then
    s = "_" .. s -- Inhibit Openbox hotkey mechanism
  end
  if s:find("%", 1, true) then
    s = url.unescape(s)
  end
  return s
end

local function mk_item_tag(label, actions)
  return xml.elem("item", { label = label, table.unpack(actions)})
end

local function mk_action_tag(name, command_tag)
  return xml.elem("action", { name = name, command_tag })
end

local function mk_command_tag(cmd, args)
  return xml.elem("command"):text(quote(cmd) .. ' ' .. quote(args))
end

local function add_executable_item(m, label, cmd, args)
  m:add_direct_child(
    mk_item_tag(label, {
      mk_action_tag("Execute", mk_command_tag(cmd, args))
    }))
  return self
end

local function add_items_from_xbel(m, path, reverse_output, cnt, override_cmd)
  if not posix.access(path) then return false end

  local function clean_executable_name(s)
    return s:sub(2, -5)
  end

  local x = xml.parse(path, true)
  if not x then return false end

  local buf, c = {}, 0

  for bookmark in x:childtags() do
    local file = bookmark:get_attribs().href
    local prop = bookmark:get_elements_with_name("bookmark:application")[1]:get_attribs()
    local i = mk_item_tag(decode_url(posix.basename(file)), {
        mk_action_tag("Execute", mk_command_tag(override_cmd or clean_executable_name(prop.exec), file))
      })
    if cnt then
      if c == cnt then
        break
      else
        c = c + 1
      end
    end
    if reverse_output then
      table.insert(buf, 1, i)
    else
      table.insert(buf, i)
    end
  end

  for _,i in ipairs(buf) do
    m:add_direct_child(i)
  end
end

local function add_remove_file_item(m, path)
  m:add_direct_child(xml.elem("separator"))
  m:add_direct_child(
    mk_item_tag("Clear recent files",
      mk_action_tag("Execute", mk_command_tag("rm", "-- " .. path)))
    )
end

local function add_is_empty_message(m)
  m:add_direct_child(
    mk_item_tag("No recently used files.", {})
  )
end

local function print_menu(m)
  print(xml.tostring(m, "", "  "))
end

local function detect_xbel_path()
  local hp = os.getenv("HOME")
  local xh = os.getenv("XDG_DATA_HOME")
  local fn = "recently-used.xbel"
  local function check_path(t)
    for _,p in ipairs(t) do
      if posix.access(p) then return p end
    end
    return nil
  end
  return check_path{
    string.format("%s/%s", xf, fn),
    string.format("%s/.local/share/%s", hp, fn),
    string.format("%s/.%s", hp, fn)
  }
end

local function main()
  local xbel_path, reverse, cnt, override = detect_xbel_path(), false, false, false
  for o, optarg, opterr in posix.getopt(arg, "hf:l:o:r", {
    { "limit",    "required", 'l' },
    { "help",     "none",     'h' },
    { "file",     "required", 'f' },
    { "reverse",  "none",     'r' },
    { "open-cmd", "required", 'o' }}) do
    if o == '?' then
      printf("Invalid option or missing argument: %s", arg[opterr-1])
      return 1
    elseif o == 'h' then
      printf([[Usage: %s [-h|--help] [-f|--file XBEL] [-l|--limit NUM] [-o|--open-cmd CMD] [-r|--reverse]
Where: -h, --help       Show this message and exit.
       -f, --file       XBEL. Path to a 'recently-used.xbel' file.
                        Omit in order to attempt to auto-detect the path.
       -l, --limit      NUM. Include up to NUM items in the menu.
       -o, --open-cmd   CMD. Open files using CMD. By default, files will be
                        opened in the application they were being used with.
       -r, --reverse    Put the most-recently used items at the top of the menu.]], arg[0])
      return 0
    elseif o == 'f' then
      xbel_path = optarg
      if not posix.access(xbel_path) then
        printf("User-supplied XBEL file path is not readable: %s. Abort.", xbel_path)
        return 1
      end
    elseif o == 'l' then
      cnt = tonumber(optarg)
    elseif o == 'o' then
      override = optarg
    elseif o == 'r' then
      reverse = true
    end
  end

  add_items_from_xbel(M, xbel_path, reverse, cnt, override)

  if #M == 0 then
    add_is_empty_message(M)
  else
    add_remove_file_item(M, xbel_path)
  end

  print_menu(M)

  return 0
end

os.exit(main())
