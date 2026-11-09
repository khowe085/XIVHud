local learnable = require("lib/actionbar/learnable")

describe("learnable", function()
  it("counts an ordinary entry as usable", function()
    assert.is_true(learnable.usable({ id = 273, en = "Sleepga" }))
  end)

  it("leaves out an entry the resources mark unlearnable", function()
    assert.is_false(learnable.usable({ id = 363, en = "Sleepga", unlearnable = true }))
  end)

  it("keeps Dispelga, unlearnable in the resources but cast off the Daybreak club", function()
    assert.is_true(learnable.usable({ id = 360, en = "Dispelga", unlearnable = true }))
  end)
end)
