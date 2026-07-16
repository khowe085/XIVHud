# Lua Guide for programmers

> Mirrored from the Windower forums thread "Lua Guide for programmers"
> (topic 697). Reproduced here because the canonical forum URL now 404s; the
> only reachable copy is a static sharelink archive (see CLAUDE.md references).
> This is the original author's text, lightly reformatted so the code blocks
> survive as Markdown. Prose and code are otherwise as written — including the
> author's own typos in the examples (e.g. `winodwer`).

Since Lua will be of interest to anyone with moderate programming skills, but at the same time has some oddities that programmers from other languages or environments will find... well, odd, I thought I'd write up my experiences learning Lua to help others avoid some Lua beginner's mistakes.

## What's familiar?

As many interpreted scripting languages, Lua has a focus on list management and string manipulation. Lists can be explicitly declared using braces: `list = {1, 2, 3}`.

Design aspects in keywords:

- Interpreted
- Dynamically and weakly typed
- Operator overloading
- First class functions
- Case-sensitive
- Object-oriented (ish)

### Objects

Lua provides an object-oriented interface, although it's not natively object-oriented. Class methods are accessed by the `.` (dot) operator, while accessing object methods is done by the `:` (colon) operator. Assuming a class `cls`, an object `obj` and a method `method`, these two are the same:

```lua
cls.method(obj, arg1, arg2, ...)
obj:method(arg1, arg2, ...)
```

Programming for Windower, you'll mostly need the string and table classes. See the Lua 5.1 API for a complete reference.

Lua also has a null value named `nil`, with a few special properties described below.

### Scoping and syntax

Lua does not use braces to denote blocks; it uses `do`, `then` and similar tokens to begin a block, and `end` to end it. Like JavaScript, it does not usually require semicolons to end a statement.

### Types and coercion

Lua uses dynamic weak typing. It only coerces numbers to strings and vice versa, where appropriate — the operator decides the outcome (`..` is concatenation):

```lua
> = "2"+5
7
> = 4/"2"
2
> = "a"..5
a5
```

Truth-value checking: Lua treats everything as true **except `false` and `nil`**. So `if varname then ... end` checks whether `varname` is defined — but if `varname` is set to `false` it also evaluates false, so a check for `nil` should be explicit.

Use `tostring` to get a string representation of any value (needed for objects, `nil`, or booleans when outputting to the console or FFXI chatlog).

### Variadic functions

If a function is called with fewer arguments than specified, the rest are `nil`. If called with more, the extras are lost unless the function is declared variadic with `...`. **Neither case errors**, so error-checking must be implemented manually.

## What's different?

### Operators

- No in-place assignment operators at all: no `++`, `--`, `+=`, etc.
- Inequality is `~=`, not `!=`.
- Exponentiation is `^`. No native bitwise operators (use the provided BitOp library).
- Logical operators are written `and` / `or`. `or` returns the first non-falsey value — used for defaults:

```lua
foo = function(bar)
    print(bar or 10)
end

> = foo(5)
5
> = foo('baz')
baz
> = foo()
10
```

`and` returns the last non-falsey value; combined with `or` it gives a ternary:

```lua
> = true and 'this' or 'that'
this
> = false and 'this' or 'that'
that
```

**Caveat:** this breaks if the 'this' value is itself `false`.

- String concatenation is `..` (double dot). Confusingly, Lua also uses `.` (dot) for class-method access and `...` (triple dot) for variadic args.
- `#` returns the length of both tables and strings.
- New operators can't be created, but existing ones can be overloaded via metatables (reminiscent of JavaScript prototypes).

### Strings

Double `"..."` and single `'...'` quotes are equivalent, but **neither works across multiple lines**. Multiline strings use double brackets:

```lua
[[this
is a
multiline string]]
```

There is **no built-in string split** — write your own or use `stringhelper.lua` in `/libs`.

### Comments

`--` comments to end of line. Multiline comments use `--[[ ... ]]`:

```lua
--[[this is a
multiline comment]]
```

### Tables

Tables are Lua's arrays/lists, but implemented as hash maps mapping a key to a value. `{'a','b','c','d'}` is identical to `{[1]='a', [2]='b', [3]='c', [4]='d'}`. Undefined keys return `nil`:

```lua
> t = {a=4, b='c'}
> t2 = {}
> t2[1] = t
> t2[2] = t['a']
> t2['bla'] = t[2]
> = t2[2]
4
```

**Gotcha:** because undefined keys return `nil`, iterating over integer keys stops as soon as it hits a `nil`, even if higher keys still have values.

Tables with no explicit keys are **1-indexed, not 0-indexed**:

```lua
> t = {4, 5, 6}
> = t[1]
4
> = t[#t]
6
> = t[0]
nil
```

String-keyed tables can be accessed with bracket syntax (`t['bla']`) or dot syntax (`t.bla`). The "object-oriented" feature is just table-key access, with tables as objects. `:` is sugar:

```lua
> s = 'foo'
> = string.rep(s, 3)
foofoofoo
> = s:rep(3)
foofoofoo
```

It only works for function calls, and only if the "object" has the "class" table set as its metatable. There's **no built-in table slicing** — use a library function.

## Tutorial

### Assignment

Variables are **global by default**; use `local` to restrict scope:

```lua
foo = function()
    x = 5
    local y = 2
    print(x, y)
end

> foo()
5       2
> print(x, y)
5       nil
```

Append to a table with `t[#t+1] = value`:

```lua
> t = {'a', 'b', 'c'}
> t[#t+1] = 'd'
> = t[4]
d
```

Multiple assignment pairs with multiple return:

```lua
foo = function()
    return 13, 7
end

> a, b = foo()
> print(a, b)
13      7
> a, b, c = foo()
> print(a, b, c)
13      7       nil
```

### Loops

`while cond do body end`, `repeat block until condition`, and a numeric `for`:

```lua
> for i = 3, 13, 2 do print(i) end
3
5
7
9
11
13
```

The step (third value) is optional and defaults to 1. Iterator `for` uses `pairs` (all keys) and `ipairs` (consecutive integer keys from 1):

```lua
> for key, value in pairs({foo = 3, bar = 1, baz = 2}) do print(key, value) end
```

`pairs` does **not** maintain input order (it's a hashmap). `ipairs` only works for sequential integer keys with no gaps, and not for non-numeric keys.

### Functions and variadic arguments

Variadic args arrive as a raw sequence, not a table:

```lua
max = function(...)
    local a, b, c = ...
    print(a, b, c)
end

> max(1, 2, 3)
1       2       3
> max(1)
1       nil     nil
```

Wrap `...` in braces to collect into a table, then iterate:

```lua
max = function(...)
    local args = {...}
    local highest
    for i = 1, #args do
        if highest == nil or highest < args[i] then
            highest = args[i]
        end
    end
    return highest
end
```

## Handling Windower functions

### Player data and mob array

Player and mob data live in Lua tables.

- The **mob array** holds info on monsters, NPCs, PCs (including yourself) and objects, accessed by index.
- Player characters have **two IDs**: a permanent global character ID, and a per-zone **mob index** (assigned on zoning in). For anything dealing with players inside a zone, use the **index**.
- The **player array** (`windower.ffxi.get_player()`) is about your own character — equipment, inventory, job, subjob, etc. The mob array only holds what it also has for any other PC.

Get your current target's name:

```lua
player = windower.ffxi.get_player()
index = player.target_index
target = windower.ffxi.get_mob_by_index(index)
target_name = target.name
```

### Events

Addons are **event-driven** — even sending commands is done in response to events. Register with `windower.register_event(names..., handler)`. Example, reacting to a `/wave` (emote ID 8):

```lua
windower.register_event('emote', function(sender, target, emote, motion_only)
    if emote == 8 and target == winodwer.ffxi.get_player().index then -- /wave has ID 8
        local name = windower.ffxi.get_mob_by_index(sender).name
        -- Do something with name here
    end
end)
```

### Interface functions

Communicate with FFXI via Windower functions such as `windower.send_command`:

```lua
windower.register_event('emote', function(sender, target, emote, motion_only)
    if emote == 8 and target == winodwer.ffxi.get_player().index then
        local name = windower.ffxi.get_mob_by_index(sender).name
        windower.send_command('input /tell '..name..' What\'s up?') -- Escape the apostrophe
    end
end)
```

### Registering Windower commands

Send commands from the chatlog/console with `//lua command <command> [args...]` (abbreviated `//lua c`). Caught with the `addon command` event; `<command>` is what you set in the `_addon` table.

```lua
_addon.command = 'pos'

windower.register_event('addon command', function(xory)
    if xory == 'x' then
        windower.ffxi.get_mob_by_index(windower.ffxi.get_player().target_index).x_pos
    elseif xory == 'y' then
        windower.ffxi.get_mob_by_index(windower.ffxi.get_player().target_index).y_pos
    else
        windower.add_to_chat(160, 'No axis or invalid axis specified.')
    end
end)
```

`//lua c pos x` passes `x` as the first argument (`xory`).

A variadic `addon command` handler — an "MTell" that expands `//lua c mtell name1, name2, ... send <message>` into repeated `/tell`s:

```lua
windower.register_event('addon command', function(...)
    local args = {...}
    local index = 1
    local names = {}
    while args[index] ~= 'send' do
        names[#names+1] = args[index]
        index = index + 1
    end
    index = index + 1
    local words = {}
    while args[index] ~= nil do
        words[#words+1] = args[index]
        index = index + 1
    end
    local message = table.concat(words, ' ')
    local command_msg = ''
    for i = 1, #names do
        command_msg = command_msg..'input /tell '..names[i]..' '..message
        if i < #names then
            command_msg = command_msg..'; wait 2; '
        end
    end
    windower.send_command(command_msg)
end)
```

### Loading / Unloading

Use `load`/`unload` to set up state and define/remove aliases:

```lua
windower.register_event('load', function()
    windower.send_command('alias mt lua c mtell')
end)

windower.register_event('unload', function()
    windower.send_command('unalias mt')
end)
```

Now `//mt playerA playerB send sup guys` sends `sup guys` to both.

## Library functions

Libraries are included by `require('library_name')`, which searches `./` then `../libs/` for `library_name.lua`. Everything defined there is pushed into the global scope.

### Logging library (`logger`)

There's no debug mode, so log a lot. `add_to_chat(color, msg)` is verbose, needs a color number, takes only one arg, and errors on non-string concatenation. The `log` function fixes this — it stringifies every argument, joins with spaces, and outputs to the chatlog:

```lua
> require('logger')
> log('sample', 5, nil, false)
sample 5 nil false
```

For tables, `table.print` and `table.vprint` (vertical) give readable output:

```lua
> t = {1,2,3}
> table.print(t)
{1, 2, 3}
> t = {a=5, b='c', eff=false}
> table.vprint(t)
{
    a=5,
    b='c',
    eff=false
}
```

### Strings library (`strings`)

Adds methods in the string namespace, available as object methods on every string:

```lua
> require('strings')
> str = 'Random string'
> = str:at(1)   --> R
> = str:at(-4)  --> r
> str = '/a/b/c/d/'
> t = str:split('/')
> = table.concat(t, ', ')  --> a, b, c, d
> = str:slice(2, 5)  --> a/b/
> = str:slice(4)     --> b/c/d/
> = str:slice(-3)    --> /d/
```

### Tables library (`tables`)

Unlike strings, plain tables don't default to the `table` namespace for instance methods. This library introduces **T-tables**, denoted by `T`:

```lua
> require('tables')
> t_old = {1,2,3,4,5}
> = t_old:concat('/')       --> Error: attempt to call method 'concat' (a nil value)
> t_new = T{1,2,3,4,5}
> = t_new:concat('/')       --> 1/2/3/4/5
> t_trans = T(t_old)        --> convert an existing table
> = t_trans:concat('/')     --> 1/2/3/4/5
```

Define tables with `T{}` instead of `{}`. Convert existing tables (mob/player arrays) with `T()`. T-tables get `:slice`, `:map`, `:filter`, `:print`, `:vprint`, etc.:

```lua
> t = T{1,2,3,4,5,6,7,8,9,10}
> t:slice(3, 7):print()          --> {3, 4, 5, 6, 7}
> t:map(function(n) return 2*n end):print()   --> {2, 4, ..., 20}
> t:filter(function(n) return n%2 == 0 end):print()  --> {2, 4, 6, 8, 10}
```

### Maths library (`maths`)

A few functions added to the `math` namespace; also lets numbers be indexed with `:` like strings and T-tables:

```lua
> require('maths')
> = math.round(5.7)          --> 6
> = math.round(math.pi, 5)   --> 3.14159
> = math.pi:round() == math.round(math.pi, 5)  --> true
```
