local new_overlay = require("lib.overlay")
local fakes = require("tests.support.fakes")

describe("overlay", function()
  local prims, overlay

  local function box(index)
    return prims.images[index]
  end

  local function label(index)
    return prims.texts[index]
  end

  before_each(function()
    prims = fakes.prims()
    overlay = new_overlay({
      new_image = prims.new_image,
      new_text = prims.new_text,
      texture = function()
        return "addons/XIVHud/assets/overlay.png"
      end,
    })
  end)

  describe("building", function()
    it("makes a box and a label the first time a component is shown", function()
      overlay.show("parambar", 10, 20, 100, 50, true)
      assert.are.equal(1, #prims.images)
      assert.are.equal(1, #prims.texts)
      assert.are.equal("addons/XIVHud/assets/overlay.png", box(1).last.path)
    end)

    it("reuses them on later shows", function()
      overlay.show("parambar", 10, 20, 100, 50, true)
      overlay.show("parambar", 30, 40, 100, 50, true)
      assert.are.equal(1, #prims.images)
      assert.are.same({ 30, 40 }, { box(1).x, box(1).y })
    end)

    it("keeps a separate box per component", function()
      overlay.show("parambar", 10, 20, 100, 50, true)
      overlay.show("clock", 0, 0, 40, 20, true)
      assert.are.equal(2, #prims.images)
      assert.are.equal(2, #prims.texts)
    end)

    it("makes the overlay prims non-draggable and unstretched by their texture", function()
      overlay.show("parambar", 10, 20, 100, 50, true)
      assert.are.equal(false, box(1).last.draggable)
      assert.are.equal(false, box(1).last.fit)
      assert.are.equal(false, label(1).last.draggable)
    end)
  end)

  describe("showing", function()
    it("covers exactly the bounds it is given", function()
      overlay.show("parambar", 10, 20, 472, 24, true)
      assert.are.same({ 10, 20 }, { box(1).x, box(1).y })
      assert.are.same({ 472, 24 }, { box(1).width, box(1).height })
      assert.is_true(box(1).visible)
      assert.is_true(label(1).visible)
    end)

    it("names the component it is covering", function()
      overlay.show("parambar", 0, 0, 100, 50, true)
      assert.are.equal("parambar", label(1).last.text)
    end)

    it("marks a component the user has switched off", function()
      overlay.show("parambar", 0, 0, 100, 50, false)
      assert.is_not_nil(label(1).last.text:lower():find("hidden"), "got: " .. label(1).last.text)
    end)

    it("draws the two states differently", function()
      overlay.show("parambar", 0, 0, 100, 50, true)
      local enabled_color, enabled_alpha = box(1).last.color, box(1).last.alpha

      overlay.show("parambar", 0, 0, 100, 50, false)
      assert.are_not.same(enabled_color, box(1).last.color)
      assert.are_not.equal(enabled_alpha, box(1).last.alpha)
    end)

    it("puts the label inside the box", function()
      overlay.show("parambar", 100, 200, 472, 24, true)
      assert.is_true(label(1).x >= 100 and label(1).x < 572)
      assert.is_true(label(1).y >= 200 and label(1).y < 224)
    end)
  end)

  describe("hiding", function()
    it("hides a component's overlay without disposing it", function()
      overlay.show("parambar", 0, 0, 100, 50, true)
      overlay.hide("parambar")
      assert.is_false(box(1).visible)
      assert.is_false(label(1).visible)
      assert.are.equal(0, box(1).destroyed)
    end)

    it("shrugs at a component that has never been shown", function()
      assert.has_no.errors(function()
        overlay.hide("nobody")
      end)
      assert.are.equal(0, #prims.images, "hiding must not build anything")
    end)
  end)

  describe("teardown", function()
    it("disposes every prim and forgets them", function()
      overlay.show("parambar", 0, 0, 100, 50, true)
      overlay.show("clock", 0, 0, 40, 20, true)
      overlay.destroy_all()

      for _, prim in ipairs(prims.all) do
        assert.are.equal(1, prim.destroyed)
      end

      overlay.show("parambar", 0, 0, 100, 50, true)
      assert.are.equal(3, #prims.images, "a fresh box after teardown")
    end)
  end)
end)
