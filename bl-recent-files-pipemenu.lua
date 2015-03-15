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
  return string.format(f, ...)
end

local function decode_url(s)
  if s:find("%", 1, true) then
    return url.unescape(s)
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

local function add_items_from_xbel(m, path, reverse_output, override_cmd)
  if not posix.access(path) then return self end

  local function clean_executable_name(s)
    return s:sub(2, -5)
  end

  local x = xml.parse(path, true)
  if not x then return self end
  local buf = {}

  for bookmark in x:childtags() do
    local file = bookmark:get_attribs().href
    local prop = bookmark:get_elements_with_name("bookmark:application")[1]:get_attribs()
    local i = mk_item_tag(decode_url(posix.basename(file)), {
        mk_action_tag("Execute", mk_command_tag(override_cmd or clean_executable_name(prop.exec), file))
      })
    if reverse_output then
      table.insert(buf, 1, i)
    else
      table.insert(buf, i)
    end
  end

  for _,i in ipairs(buf) do
    m:add_direct_child(i)
  end

  return m
end

local function add_remove_file_item(m, path)
  m:add_direct_child(xml.elem("separator"))
  m:add_direct_child(
    mk_item_tag("Clear recent files",
      mk_action_tag("Execute", mk_command_tag("rm", "-- " .. path)))
    )
  return m
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
  local xbel_path = _G.arg[1] or detect_xbel_path()
  add_items_from_xbel(M, xbel_path)
  add_remove_file_item(M, xbel_path)
  print_menu(M)
  return 0
end

return main()
