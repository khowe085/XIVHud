local new_window = require("lib/window")
local fakes = require("tests/support/fakes")

local function call_names(prim)
  local names = {}
  for index, call in ipairs(prim.calls) do
    names[index] = call.name
  end
  return names
end

describe("window", function()
  local prims

  local function build(overrides)
    prims = fakes.prims()
    local deps = {
      new_image = prims.new_image,
      new_text = prims.new_text,
      asset = function(path)
        return "addon/" .. path
      end,
      screen = function()
        return 1920, 1080
      end,
    }
    for key, value in pairs(overrides or {}) do
      deps[key] = value
    end
    return new_window(deps)
  end

  describe("building", function()
    it("makes no prim until a pool is asked for", function()
      build()
      assert.are.equal(0, #prims.all)
    end)

    it("lays out, and declines to draw, with no deps at all", function()
      for _, bare in ipairs({ new_window(), new_window({}) }) do
        local frame = bare.frame()
        assert.are.same({ 500, 240 }, { frame.x, frame.y })
        assert.is_nil(frame.back)
        assert.is_nil(bare.pool())
      end
    end)

    it("names Windower's mouse types", function()
      local window = build()
      assert.are.same({ 0, 1, 2, 10 }, { window.MOVE, window.LEFT_DOWN, window.LEFT_UP, window.WHEEL })
    end)
  end)

  describe("inside", function()
    local rect = { x = 10, y = 20, width = 30, height = 40 }

    it("takes the left and top edges and leaves the right and bottom ones", function()
      local window = build()
      assert.is_true(window.inside(10, 20, rect))
      assert.is_true(window.inside(39, 59, rect))
      assert.is_false(window.inside(40, 59, rect))
      assert.is_false(window.inside(39, 60, rect))
      assert.is_false(window.inside(9, 20, rect))
      assert.is_false(window.inside(10, 19, rect))
    end)

    it("answers false rather than throwing on a missing rect or a non-number point", function()
      local window = build()
      assert.is_false(window.inside(10, 20, nil))
      assert.is_false(window.inside("10", 20, rect))
      assert.is_false(window.inside(nil, 20, rect))
      assert.is_false(window.inside(10, nil, rect))
      assert.is_false(window.inside(10, "20", rect))
    end)
  end)

  describe("draw_rows", function()
    it("writes, places and shows a prim per line", function()
      local window = build()
      local list = { prims.new_text(), prims.new_text() }
      window.draw_rows(list, { { text = "one", x = 5, y = 6 }, { text = "two", x = 7, y = 8 } })
      assert.are.equal("one", list[1].last.text)
      assert.are.same({ 5, 6 }, { list[1].x, list[1].y })
      assert.is_true(list[1].visible)
      assert.are.equal("two", list[2].last.text)
      assert.are.same({ 7, 8 }, { list[2].x, list[2].y })
      assert.is_true(list[2].visible)
    end)

    it("hides every prim past the last line, once", function()
      local window = build()
      local list = { prims.new_text(), prims.new_text(), prims.new_text() }
      window.draw_rows(list, { { text = "one", x = 0, y = 0 } })
      assert.are.same({ "hide" }, call_names(list[2]))
      assert.are.same({ "hide" }, call_names(list[3]))
      window.draw_rows(list, {})
      assert.is_false(list[1].visible)
    end)
  end)

  describe("a pool", function()
    it("is nil, and builds nothing, when a prim dep is missing", function()
      for _, missing in ipairs({ "new_image", "new_text", "asset" }) do
        prims = fakes.prims()
        local deps = { new_image = prims.new_image, new_text = prims.new_text, asset = tostring }
        deps[missing] = nil
        assert.is_nil(new_window(deps).pool(), missing)
        assert.are.equal(0, #prims.all, missing)
      end
    end)

    it("styles a text, hidden, in the window's own size", function()
      local pool = build().pool()
      local text = pool.text()
      assert.are.equal("sans-serif", text.last.font)
      assert.are.equal(18, text.font_size)
      assert.are.same({ 255, 255, 255 }, text.last.color)
      assert.are.equal(1, text.last.stroke_width)
      assert.are.same({ 0, 0, 0 }, text.last.stroke_color)
      assert.are.equal(255, text.last.stroke_alpha)
      assert.is_false(text.last.bg_visible)
      assert.is_false(text.last.right_justified)
      assert.are.equal("", text.last.text)
      assert.is_false(text.visible)
    end)

    it("takes the font family from its client, asked once per pool", function()
      local asked = 0
      local window = build({
        font = function()
          asked = asked + 1
          return "Arial"
        end,
      })
      local pool = window.pool()
      assert.are.equal("Arial", pool.text().last.font)
      pool.text()
      assert.are.equal(1, asked)
      window.pool()
      assert.are.equal(2, asked)
    end)

    it("builds an image with or without art, hidden", function()
      local pool = build().pool()
      local with = pool.image("assets/own/panel.png")
      assert.are.equal("addon/assets/own/panel.png", with.last.path)
      assert.is_false(with.last.fit)
      assert.is_false(with.last.draggable)
      assert.are.same({ 1, 1 }, with.last.repeat_xy)
      assert.are.same({ 255, 255, 255 }, with.last.color)
      assert.is_false(with.visible)
      local without = pool.image()
      assert.is_nil(without.last.path)
      assert.is_false(without.last.fit)
      assert.is_false(without.visible)
    end)

    it("draws its backdrop from the black square", function()
      local pool = build().pool()
      assert.are.equal("addon/assets/own/black-square.png", pool.backdrop().last.path)
    end)

    it("builds lists of exactly the count and kind asked for, in creation order", function()
      local pool = build().pool()
      local texts, images = pool.texts(3), pool.images(2)
      assert.are.equal(3, #texts)
      assert.are.equal(2, #images)
      assert.are.same({ prims.all[1], prims.all[2], prims.all[3] }, texts)
      assert.are.same({ prims.all[4], prims.all[5] }, images)
      for _, text in ipairs(texts) do
        assert.are.equal("text", text.kind)
      end
      for _, image in ipairs(images) do
        assert.are.equal("image", image.kind)
        assert.is_nil(image.last.path)
      end
    end)

    it("hides every prim as the last thing it does to it", function()
      -- The fake starts a prim invisible, so `visible` alone cannot say
      -- whether it was hidden.
      local pool = build().pool()
      for _, prim in ipairs({ pool.text(), pool.image(), pool.image("assets/own/panel.png"), pool.backdrop() }) do
        assert.are.equal("hide", prim.calls[#prim.calls].name)
      end
    end)

    it("destroys every prim it made exactly once, however often it is asked", function()
      local window = build()
      local pool = window.pool()
      pool.backdrop()
      pool.texts(3)
      pool.image()
      pool.destroy()
      pool.destroy()
      assert.are.equal(5, #prims.all)
      for _, prim in ipairs(prims.all) do
        assert.are.equal(1, prim.destroyed)
      end
      window.pool().text()
      assert.are.equal(6, #prims.all, "a second pool builds fresh prims")
      assert.are.equal(0, prims.all[6].destroyed)
    end)
  end)

  describe("position", function()
    it("answers nil for anything that is not a pair of numbers", function()
      local window = build()
      assert.is_nil(window.position(nil))
      assert.is_nil(window.position("500,240"))
      assert.is_nil(window.position(5))
      assert.is_nil(window.position(true))
      assert.is_nil(window.position({ x = "a", y = 1 }))
      assert.is_nil(window.position({ x = 1 }))
    end)

    it("keeps the whole window on screen", function()
      local window = build()
      assert.are.same({ x = 1000, y = 480 }, window.position({ x = 9000, y = 9000 }))
      assert.are.same({ x = 0, y = 0 }, window.position({ x = -5, y = -5 }))
      assert.are.same({ x = 300, y = 200 }, window.position({ x = 300, y = 200 }))
    end)

    it("pins a window larger than the screen to the top left", function()
      local window = build({
        screen = function()
          return 800, 500
        end,
      })
      assert.are.same({ x = 0, y = 0 }, window.position({ x = 300, y = 200 }))
    end)

    it("answers a table of its own", function()
      local stored = { x = 300, y = 200 }
      assert.are_not.equal(stored, build().position(stored))
    end)

    it("reads a position that is not a real number as an edge of the screen", function()
      -- These files are Lua, so `0/0` can be written into one by hand.
      local window = build()
      assert.are.same({ x = 0, y = 0 }, window.position({ x = 0 / 0, y = 0 / 0 }))
      assert.are.same({ x = 1000, y = 0 }, window.position({ x = math.huge, y = -math.huge }))
    end)

    it("assumes 1920x1080 when the screen cannot be read", function()
      assert.are.same({ x = 1000, y = 480 }, new_window({}).position({ x = 9000, y = 9000 }))
      local unread = build({
        screen = function()
          return nil
        end,
      })
      assert.are.same({ x = 1000, y = 480 }, unread.position({ x = 9000, y = 9000 }))
    end)
  end)

  describe("frame", function()
    local function rect(x, y, width, height)
      return { x = x, y = y, width = width, height = height }
    end

    it("centres the window and lays its controls out, back included", function()
      local frame = build({ back = true }).frame()
      assert.are.same(
        { 500, 240, 920, 600 },
        { frame.x, frame.y, frame.width, frame.height },
        "dead centre of 1920x1080"
      )
      assert.are.same(rect(510, 250, 90, 26), frame.back)
      assert.are.same(rect(1360, 250, 50, 26), frame.close)
      assert.are.same({ x = 612, y = 250 }, frame.title)
      assert.are.same(rect(600, 240, 820, 36), frame.header)
      assert.are.same({ x = 510, y = 276 }, frame.subhead)
      assert.are.same(rect(510, 302, 900, 520), frame.body)
    end)

    it("gives the title strip the back control's width when there is none", function()
      local frame = build().frame()
      assert.is_nil(frame.back)
      assert.are.same({ x = 510, y = 250 }, frame.title)
      assert.are.same(rect(500, 240, 920, 36), frame.header)
      assert.are.same(rect(1360, 250, 50, 26), frame.close)
    end)

    it("pins a centred frame larger than the screen to the top left", function()
      local frame = build({
        screen = function()
          return 800, 500
        end,
      }).frame()
      assert.are.same({ 0, 0 }, { frame.x, frame.y })
    end)

    it("centres on a whole pixel, rounded down, on an odd-sized screen", function()
      local frame = build({
        screen = function()
          return 1921, 1081
        end,
      }).frame()
      assert.are.same({ 500, 240 }, { frame.x, frame.y })
    end)

    it("sits where it is told, unclamped", function()
      local frame = build().frame({ x = -50, y = 5000 })
      assert.are.same({ -50, 5000 }, { frame.x, frame.y })
      assert.are.same({ -40, 5010 }, { frame.subhead.x, frame.title.y })
    end)

    it("answers a fresh table every time", function()
      local window = build({ back = true })
      local first = window.frame()
      first.back = nil
      first.body.x = 0
      local second = window.frame()
      assert.are_not.equal(first, second)
      assert.is_not_nil(second.back)
      assert.are.equal(510, second.body.x)
    end)
  end)

  describe("metrics", function()
    it("names the numbers a client lays its rows out with", function()
      local window = build()
      assert.are.same({ font_size = 18, row_height = 26, gap = 12, body_rows = 20 }, window.metrics())
      assert.are_not.equal(window.metrics(), window.metrics())
    end)

    it("counts exactly the rows the body holds", function()
      local window = build()
      local metrics = window.metrics()
      assert.are.equal(metrics.body_rows * metrics.row_height, window.frame().body.height)
    end)
  end)

  describe("paged", function()
    local column = { x = 100, y = 200, width = 300 }

    local function items(count)
      local list = {}
      for index = 1, count do
        list[index] = "item " .. index
      end
      return list
    end

    it("lays one page of a list into a column, a row apart", function()
      local rows, pages, page = build().paged(items(20), column, 19, 1)
      assert.are.equal(19, #rows)
      assert.are.equal(2, pages)
      assert.are.equal(1, page)
      assert.are.same({ item = "item 2", index = 2, x = 100, y = 226, width = 300, height = 26 }, rows[2])
    end)

    it("brings a page past the end back to the last one", function()
      local rows, pages, page = build().paged(items(20), column, 19, 5)
      assert.are.equal(2, pages)
      assert.are.equal(2, page)
      assert.are.equal(1, #rows)
      assert.are.equal(20, rows[1].index)
      assert.are.equal(200, rows[1].y)
    end)

    it("counts no empty last page when the list fills its pages exactly", function()
      local rows, pages, page = build().paged(items(38), column, 19, 2)
      assert.are.equal(2, pages)
      assert.are.equal(2, page)
      assert.are.equal(19, #rows)
    end)

    it("answers one empty page for an empty list", function()
      local rows, pages, page = build().paged({}, column, 19, 1)
      assert.are.same({}, rows)
      assert.are.equal(1, pages)
      assert.are.equal(1, page)
    end)
  end)

  describe("control_at", function()
    local function centre(rect)
      return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    it("finds close before the title strip it sits inside", function()
      local window = build({ back = true })
      local frame = window.frame()
      local x, y = centre(frame.close)
      assert.is_true(window.inside(x, y, frame.header), "the strip covers it")
      assert.are.same({ kind = "close", rect = frame.close }, window.control_at(frame, x, y))
    end)

    it("finds back, and the strip beside it", function()
      local window = build({ back = true })
      local frame = window.frame()
      assert.are.same({ kind = "back", rect = frame.back }, window.control_at(frame, centre(frame.back)))
      assert.are.same(
        { kind = "header", rect = frame.header },
        window.control_at(frame, frame.title.x + 10, frame.title.y)
      )
    end)

    it("leaves the corner inert once a client takes back off its frame", function()
      local window = build({ back = true })
      local frame = window.frame()
      local x, y = centre(frame.back)
      frame.back = nil
      assert.is_nil(window.control_at(frame, x, y))
    end)

    it("drags from the top left corner of a window that never had a back", function()
      local window = build()
      local frame = window.frame()
      assert.are.equal("header", window.control_at(frame, frame.x + 20, frame.y + 5).kind)
    end)

    it("answers nil in the body, and for no frame at all", function()
      local window = build({ back = true })
      local frame = window.frame()
      assert.is_nil(window.control_at(frame, centre(frame.body)))
      assert.is_nil(window.control_at(nil, 510, 250))
    end)
  end)

  describe("draw_frame", function()
    local function chrome_prims(pool, with_back)
      return {
        window_bg = pool.backdrop(),
        back = with_back and pool.text() or nil,
        close = pool.text(),
        title = pool.text(),
        subhead = pool.text(),
      }
    end

    local function calls_since(prim, count)
      local names = {}
      for index = count + 1, #prim.calls do
        names[#names + 1] = prim.calls[index].name
      end
      return names
    end

    it("draws the backdrop over the whole frame, dimmed black", function()
      local window = build({ back = true })
      local drawn = chrome_prims(window.pool(), true)
      window.draw_frame(drawn, window.frame(), "Title", "Subhead")
      assert.is_true(drawn.window_bg.visible)
      assert.are.same({ 0, 0, 0 }, drawn.window_bg.last.color)
      assert.are.equal(220, drawn.window_bg.last.alpha)
      assert.are.same({ 500, 240, 920, 600 }, {
        drawn.window_bg.x,
        drawn.window_bg.y,
        drawn.window_bg.width,
        drawn.window_bg.height,
      })
    end)

    it("writes the two controls, the title and the subhead where the frame puts them", function()
      local window = build({ back = true })
      local drawn = chrome_prims(window.pool(), true)
      local frame = window.frame()
      window.draw_frame(drawn, frame, "Title", "Subhead")
      assert.are.equal("[ < back ]", drawn.back.last.text)
      assert.are.same({ frame.back.x, frame.back.y }, { drawn.back.x, drawn.back.y })
      assert.are.equal("[ X ]", drawn.close.last.text)
      assert.are.same({ frame.close.x, frame.close.y }, { drawn.close.x, drawn.close.y })
      assert.are.equal("Title", drawn.title.last.text)
      assert.are.same({ frame.title.x, frame.title.y }, { drawn.title.x, drawn.title.y })
      assert.are.equal("Subhead", drawn.subhead.last.text)
      assert.are.same({ frame.subhead.x, frame.subhead.y }, { drawn.subhead.x, drawn.subhead.y })
      for _, key in ipairs({ "back", "close", "title", "subhead" }) do
        assert.is_true(drawn[key].visible, key)
      end
    end)

    it("hides back on a frame that carries none", function()
      local window = build({ back = true })
      local drawn = chrome_prims(window.pool(), true)
      local frame = window.frame()
      window.draw_frame(drawn, frame, "Title", "Subhead")
      frame.back = nil
      local before = #drawn.back.calls
      window.draw_frame(drawn, frame, "Title", "Subhead")
      assert.are.same({ "hide" }, calls_since(drawn.back, before))
    end)

    it("draws a window that was never given a back prim", function()
      local window = build()
      local drawn = chrome_prims(window.pool(), false)
      window.draw_frame(drawn, window.frame(), "Title", "Subhead")
      assert.is_true(drawn.close.visible)
    end)

    it("hides all of it again, one call apiece", function()
      local window = build({ back = true })
      local drawn = chrome_prims(window.pool(), true)
      window.draw_frame(drawn, window.frame(), "Title", "Subhead")
      local before = {}
      for key, prim in pairs(drawn) do
        before[key] = #prim.calls
      end
      window.hide_frame(drawn)
      for key, prim in pairs(drawn) do
        assert.are.same({ "hide" }, calls_since(prim, before[key]), key)
      end
      window.hide_frame(chrome_prims(window.pool(), false))
    end)
  end)

  describe("a press", function()
    local row = { kind = "row", rect = { x = 600, y = 400, width = 200, height = 26 } }

    local function header_press(window, frame)
      local target = window.control_at(frame, frame.header.x + 20, frame.header.y + 5)
      window.press(target, frame.header.x + 20, frame.header.y + 5, frame)
      return target
    end

    it("is nothing until one is armed", function()
      local window = build()
      assert.is_nil(window.pressed())
      assert.is_nil(window.motion(610, 410))
      assert.is_nil(window.release())
    end)

    it("is armed on its target, and replaced by the next one", function()
      local window = build()
      window.press(row, 610, 410, window.frame())
      local armed = window.pressed()
      assert.are.equal(row, armed.target)
      assert.are.equal(row.rect, armed.rect)
      assert.is_false(armed.drag)
      local other = { kind = "row", rect = { x = 600, y = 426, width = 200, height = 26 } }
      window.press(other, 610, 430, window.frame())
      assert.are.equal(other, window.pressed().target)
    end)

    it("is handed back once by release, and dropped by cancel", function()
      local window = build()
      window.press(row, 610, 410, window.frame())
      assert.are.equal(row, window.release().target)
      assert.is_nil(window.release())
      window.press(row, 610, 410, window.frame())
      window.cancel()
      assert.is_nil(window.pressed())
      assert.is_nil(window.release())
    end)

    it("stays a click for as long as the cursor is on what it started on", function()
      local window = build()
      window.press(row, 610, 410, window.frame())
      assert.are.equal("click", window.motion(612, 411))
      assert.is_false(window.pressed().drag)
    end)

    it("becomes a drag when the cursor leaves, and stays one when it comes back", function()
      local window = build()
      window.press(row, 610, 410, window.frame())
      assert.are.equal("start", window.motion(610, 500))
      assert.is_true(window.pressed().drag)
      assert.are.equal("drag", window.motion(610, 520))
      assert.are.equal("drag", window.motion(610, 410))
      assert.is_true(window.release().drag)
    end)

    it("answers no position for a drag that is not the title strip's", function()
      local window = build()
      window.press(row, 610, 410, window.frame())
      local phase, x, y = window.motion(610, 500)
      assert.are.same({ "start" }, { phase, x, y })
      assert.is_nil(window.release().position)
    end)

    it("reads a slip inside the title strip as a click", function()
      local window = build()
      local frame = window.frame()
      header_press(window, frame)
      assert.are.equal("click", window.motion(frame.header.x + 22, frame.header.y + 6))
      assert.is_nil(window.release().position, "so nothing is there to save")
    end)

    it("moves the window with the grab point kept under the cursor", function()
      local window = build()
      local frame = window.frame()
      header_press(window, frame)
      local phase, x, y = window.motion(frame.header.x + 20 - 200, frame.header.y + 5 - 150)
      assert.are.same({ "start", frame.x - 200, frame.y - 150 }, { phase, x, y })
      phase, x, y = window.motion(frame.header.x + 20 - 210, frame.header.y + 5 - 150)
      assert.are.same({ "drag", frame.x - 210, frame.y - 150 }, { phase, x, y })
      assert.are.same({ x = frame.x - 210, y = frame.y - 150 }, window.release().position)
    end)

    it("arms a title-strip press given no frame, as one that moves nothing", function()
      local window = build()
      local frame = window.frame()
      local target = window.control_at(frame, frame.header.x + 20, frame.header.y + 5)
      window.press(target, frame.header.x + 20, frame.header.y + 5, nil)
      local phase, x, y = window.motion(-5000, -5000)
      assert.are.same({ "start" }, { phase, x, y })
      assert.is_nil(window.release().position)
    end)

    it("keeps a dragged window on screen at both corners", function()
      local window = build()
      local frame = window.frame()
      header_press(window, frame)
      local _, x, y = window.motion(-5000, -5000)
      assert.are.same({ 0, 0 }, { x, y })
      _, x, y = window.motion(9000, 9000)
      assert.are.same({ 1000, 480 }, { x, y })
    end)

    it("carries whatever its client hangs on it through to the release", function()
      local window = build()
      window.press(row, 610, 410, window.frame())
      window.pressed().ghost = "a ghost"
      assert.are.equal("a ghost", window.release().ghost)
    end)
  end)
end)
