local kebab = require("components/crossbar/kebab")

describe("crossbar kebab", function()
  it("lowercases and hyphenates spaces", function()
    assert.equal("dragon-kick", kebab("Dragon Kick"))
  end)

  it("drops colons", function()
    assert.equal("addendum-white", kebab("Addendum: White"))
  end)

  it("drops apostrophes", function()
    assert.equal("ascetics-fury", kebab("Ascetic's Fury"))
  end)

  it("keeps hyphens that were already there", function()
    assert.equal("kawahori-ogi", kebab("Kawahori-Ogi"))
  end)

  it("keeps slashes and question marks", function()
    assert.equal("a/b-c", kebab("A/B C"))
    assert.equal("yawn?", kebab("Yawn?"))
  end)

  it("returns only the name, never a gsub count", function()
    local name, extra = kebab("Dragon Kick")
    assert.equal("dragon-kick", name)
    assert.is_nil(extra)
  end)
end)
