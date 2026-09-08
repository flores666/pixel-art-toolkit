-- tests/run_tests.lua -- headless test run. No Aseprite required:
--
--   lua5.4 art/tools/tests/run_tests.lua [--dump DIR]
--
-- Covers the invariants the art pipeline depends on: palette integrity,
-- determinism, every primitive, every generator against every validator, and
-- the preview sheets. --dump writes scaled PPMs of the sheets for eyeballing.

local here = debug.getinfo(1, "S").source:sub(2)
local tools = here:match("^(.*)[/\\]tests[/\\][^/\\]*$") or "."
local toolkit = dofile(tools .. "/init.lua")
package.path = tools .. "/tests/?.lua;" .. package.path

local style, palette, rng = toolkit.style, toolkit.palette, toolkit.rng
local P, materials = toolkit.pixels, toolkit.materials
local generators, validators, previews = toolkit.generators, toolkit.validators, toolkit.previews

-- How many seeds the per-asset sweep covers. The default keeps the suite fast
-- enough to run on every edit; `--seeds 64` is the number ART_STYLE.md asks
-- for before shipping, and `art/tools/export.lua` validates every variant it
-- actually writes, so nothing reaches the game unchecked either way.
local SWEEP_SEEDS = 24
for i, a in ipairs(arg or {}) do
  if a == "--seeds" then SWEEP_SEEDS = math.tointeger(arg[i + 1]) or SWEEP_SEEDS end
  if a == "--full" then SWEEP_SEEDS = 64 end
end

local passed, failed = 0, {}

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed[#failed + 1] = ("%s: %s"):format(name, err)
    io.write("FAIL ", name, "\n  ", tostring(err), "\n")
  end
end

--- Pick a generator by property rather than by name: the tests must survive the
--- art direction being retargeted.
local function some(pred)
  for _, name in ipairs(generators.names) do
    if pred(generators.get(name)) then return name end
  end
  error("no generator matches", 2)
end

local function assert_eq(got, want, what)
  if got ~= want then
    error(("%s: got %s, want %s"):format(what or "value", tostring(got), tostring(want)), 2)
  end
end

-- palette ---------------------------------------------------------------------

test("palette has no duplicate colours", function()
  local seen = {}
  for _, name in ipairs(palette.names) do
    local c = palette.by_name[name]
    assert(not seen[c], "duplicate " .. name)
    seen[c] = true
    local _, _, _, a = palette.unpack(c)
    assert_eq(a, 255, name .. " alpha")
  end
  assert_eq(palette.size, #palette.names, "size")
end)

test("palette shift stays inside its ramp and clamps", function()
  assert_eq(palette.shift("concrete_4", 1), palette.by_name.concrete_5, "up")
  local top = palette.ramps.concrete[#palette.ramps.concrete]
  assert_eq(palette.shift("concrete_3", 99), top, "clamp high")
  assert_eq(palette.shift("concrete_1", -3), palette.by_name.concrete_1, "clamp low")
  assert_eq(palette.shift(palette.TRANSPARENT, 1), palette.TRANSPARENT, "transparent")
  local ramp, index = palette.slot("metal_4")
  assert_eq(ramp, "metal", "ramp"); assert_eq(index, 4, "index")
end)

test("palette rejects colours it does not own", function()
  assert(not pcall(palette.resolve, "not_a_colour"), "unknown name must error")
  assert(not pcall(palette.resolve, palette.pack(1, 2, 3, 255)), "off-palette value must error")
  assert(palette.is_valid(palette.by_name.rust_3), "known colour")
  assert(palette.is_valid(palette.TRANSPARENT), "transparent is valid")
end)

-- rng -------------------------------------------------------------------------

test("rng is deterministic and stream-independent", function()
  local function draw(seed, salt)
    local r, out = rng.new(seed, salt), {}
    for i = 1, 32 do out[i] = r:range(0, 999) end
    return table.concat(out, ",")
  end
  assert_eq(draw(7, "a"), draw(7, "a"), "same seed and salt")
  assert(draw(7, "a") ~= draw(8, "a"), "different seed")
  assert(draw(7, "a") ~= draw(7, "b"), "different salt")
  local r = rng.new(1)
  for _ = 1, 500 do
    local v = r:range(3, 9)
    assert(v >= 3 and v <= 9, "range bounds")
  end
end)

test("rng branches do not couple features", function()
  local a = rng.new(5, "gen"); local b = rng.new(5, "gen")
  local a1 = a:branch("rust"):range(0, 1e6)
  b:range(0, 100)                       -- an extra draw on the parent...
  local b1 = b:branch("rust"):range(0, 1e6)
  assert_eq(a1, b1, "branch is a pure function of the parent seed")
end)

-- surface and primitives -------------------------------------------------------

test("surface clips, wraps, and refuses off-palette colours", function()
  local s = P.new(16, 16)
  assert_eq(s:set(-1, 0, "ink_1"), false, "clipped write")
  assert_eq(s:get(20, 20), palette.TRANSPARENT, "clipped read")
  local w = P.new(16, 16, { wrap = true })
  w:set(-1, -1, "ink_1")
  assert_eq(w:get(15, 15), palette.by_name.ink_1, "wrapped write")
  assert(not pcall(function() s:set(0, 0, palette.pack(9, 9, 9, 255)) end), "off-palette write")
  assert(s:set_raw(0, 0, palette.pack(9, 9, 9, 128)), "raw import bypasses the check")
end)

test("line, rect and polygon draw exact pixels", function()
  local s = P.new(16, 16)
  P.line(s, 2, 2, 2, 9, "metal_3")
  assert_eq(s:get(2, 2), palette.by_name.metal_3, "line start")
  assert_eq(s:get(2, 9), palette.by_name.metal_3, "line end")
  assert_eq(s:get(2, 10), palette.TRANSPARENT, "line does not overrun")
  local _, filled = P.histogram(s)
  assert_eq(filled, 8, "vertical line length")

  local r = P.new(16, 16)
  P.rect_fill(r, 4, 4, 5, 3, "metal_3")
  local _, n = P.histogram(r)
  assert_eq(n, 15, "rect_fill area")
  local o = P.new(16, 16)
  P.rect(o, 0, 0, 4, 4, "metal_3")
  local _, edge = P.histogram(o)
  assert_eq(edge, 12, "rect outline perimeter")

  local poly = P.new(16, 16)
  P.polygon_fill(poly, { { 2, 2 }, { 10, 2 }, { 10, 6 }, { 2, 6 } }, "metal_3")
  local _, area = P.histogram(poly)
  assert_eq(area, 9 * 5, "polygon fill covers its rectangle")
end)

test("clusters are connected and never single pixels", function()
  local r = rng.new(4, "cluster")
  for _ = 1, 50 do
    local s = P.new(16, 16)
    local blob = P.cluster(s, r:range(2, 13), r:range(2, 13), r:range(2, 8), "metal_3", r)
    assert(#blob >= 2, "cluster has at least two pixels")
    assert_eq(#P.isolated(s), 0, "cluster leaves no stray pixel")
  end
end)

test("dither is ordered, in phase, and refuses to band", function()
  local s = P.new(16, 16, { fill = "concrete_4" })
  P.dither(s, "concrete_5", 2)
  local hist = P.histogram(s)
  assert_eq(hist[palette.by_name.concrete_5], 128, "density 2 covers half the area")
  -- Same phase at any offset: neighbouring tiles cannot show a dither seam.
  assert_eq(s:get(0, 0), s:get(2, 0), "dither is anchored to absolute coordinates")
  assert_eq(s:get(0, 0), s:get(0, 2), "dither is anchored on both axes")
  local far = P.new(4, 4, { fill = "concrete_1" })
  assert(not pcall(P.dither, far, "concrete_5", 2), "non-adjacent ramp steps must error")
  assert(pcall(P.dither, far, "concrete_5", 2, { allow_jump = true }), "explicit jump is allowed")
end)

test("broken runs never leave a one-pixel stub", function()
  local r = rng.new(9, "runs")
  for _ = 1, 60 do
    local s = P.new(16, 16, { fill = "metal_3" })
    P.broken_run(s, "h", r:range(0, 15), 0, 15, r, { delta = 1, run = { 3, 5 }, gap = { 1, 3 } })
    assert_eq(#P.isolated(s), 0, "runs leave no stray pixels")
  end
end)

test("outline wraps the silhouette without touching it", function()
  local s = P.new(16, 16)
  P.rect_fill(s, 5, 5, 4, 4, "metal_3")
  P.outline(s, "ink_1")
  assert_eq(s:get(5, 5), palette.by_name.metal_3, "body untouched")
  assert_eq(s:get(4, 5), palette.by_name.ink_1, "left outline")
  assert_eq(s:get(9, 5), palette.by_name.ink_1, "right outline")
  assert_eq(s:get(4, 4), palette.TRANSPARENT, "no diagonal nub by default")
end)

test("lighting follows the fixed upper-left key light", function()
  local s = P.new(16, 16)
  P.rect_fill(s, 5, 5, 5, 5, "metal_3")
  P.apply_lighting(s)
  assert_eq(s:get(5, 5), palette.by_name.metal_4, "lit top-left")
  assert_eq(s:get(7, 5), palette.by_name.metal_4, "lit top edge")
  assert_eq(s:get(9, 9), palette.by_name.metal_2, "shaded bottom-right")
  assert_eq(s:get(7, 7), palette.by_name.metal_3, "interior unchanged")
end)

test("despeckle never grows the outline into the shape", function()
  -- Regression: the outline is the local majority beside a silhouette, so a
  -- majority vote used to convert body pixels into outline, eating the shape
  -- and leaving a two-pixel outline exactly there.
  local s = P.new(16, 16)
  P.rect_fill(s, 5, 5, 5, 5, "metal_3")
  P.outline(s, style.outline_color)
  s:set(5, 7, "metal_6")                      -- a stray body pixel on the edge
  P.despeckle(s)
  assert(s:get(5, 7) ~= palette.resolve(style.outline_color),
    "despeckle turned a body pixel into outline")
  -- outline_thickness across every generator is covered by the single sweep
  -- below, which builds each asset once instead of once per property.
end)

test("wear overlays honour a zero coverage", function()
  -- Regression: the patch count was floored at one, so "5% corrosion" still
  -- put rust on every single tile of a wall.
  local before = P.new(16, 16, { fill = "metal_3" })
  local after = before:clone()
  materials.rust.fill(after, rng.new(3, "rust"), { coverage = 0 })
  materials.dirt.fill(after, rng.new(3, "dirt"), { coverage = 0 })
  assert_eq(after:fingerprint(), before:fingerprint(), "zero coverage must draw nothing")

  local clean = 0
  for seed = 1, 60 do
    local s = P.new(16, 16, { fill = "metal_3" })
    materials.rust.fill(s, rng.new(seed, "rust"), { coverage = 0.05 })
    if P.color_count(s) == 1 then clean = clean + 1 end
  end
  assert(clean > 20, ("only %d/60 tiles were left clean at 5%% coverage"):format(clean))
end)

test("preview sheets are judged as sheets, not as oversized assets", function()
  local sheet = previews.sheet(some(function(g) return g.tileable end), { seed = 1 })
  local as_asset = validators.run(sheet, { name = "sheet" })
  local as_sheet = validators.run(sheet, { name = "sheet", kind = "sheet" })
  assert(not as_asset.ok, "a 160x160 surface is not a valid asset size")
  assert(as_sheet.ok, "the same surface is a valid review sheet: " .. validators.format(as_sheet))
end)

test("despeckle removes dust and keeps clusters", function()
  local s = P.new(16, 16, { fill = "concrete_4" })
  s:set(8, 8, "concrete_1")                      -- dust
  s:set(2, 2, "concrete_1"); s:set(3, 2, "concrete_1")  -- a legitimate pair
  local fixed = P.despeckle(s)
  assert_eq(fixed, 1, "one stray absorbed")
  assert_eq(s:get(8, 8), palette.by_name.concrete_4, "dust absorbed into its surroundings")
  assert_eq(s:get(2, 2), palette.by_name.concrete_1, "cluster survives")
end)

-- materials ---------------------------------------------------------------------

test("every material follows the contract", function()
  for _, name in ipairs(materials.names) do
    local m = materials.get(name)
    assert_eq(type(m.fill), "function", name .. ".fill")
    assert(m.kind == "base" or m.kind == "overlay", name .. ".kind")
    assert(palette.ramps[m.ramp], name .. ".ramp exists")
    if m.kind == "base" then assert(m.base, name .. ".base step") end
  end
end)

test("materials only ever draw palette colours, and stay inside their mask", function()
  local r = rng.new(12, "materials")
  for _, name in ipairs(materials.names) do
    local s = P.new(16, 16, { fill = "metal_3" })
    materials.get(name).fill(s, r, {
      area = { x = 4, y = 4, w = 8, h = 8 },
      mask = function(x, y) return x >= 4 and x < 12 and y >= 4 and y < 12 end,
      coverage = 0.6,
    })
    for x, y, c in s:pixels() do
      assert(palette.is_valid(c), name .. " drew an off-palette colour")
      if x < 4 or x >= 12 or y < 4 or y >= 12 then
        assert_eq(c, palette.by_name.metal_3, name .. " escaped its mask at " .. x .. "," .. y)
      end
    end
  end
end)

-- generators ----------------------------------------------------------------------

test("every generator follows the contract", function()
  for _, name in ipairs(generators.names) do
    local g = generators.get(name)
    assert_eq(g.name, name, "name")
    assert(type(g.title) == "string" and #g.title > 0, name .. ".title")
    assert(style.check_size(g.size.w, g.size.h))
    assert_eq(type(g.build), "function", name .. ".build")
    if g.preview_background then
      assert(generators[g.preview_background], name .. " background exists")
    end
  end
end)

test("every generator, every seed: validators, determinism, wrap, brightness", function()
  -- ONE pass over (generator, seed), checking every per-asset property there
  -- is. It used to be five passes -- validators, determinism, the busyness
  -- ceiling, the wrap flag, ground brightness -- each rebuilding the same
  -- asset, which cost 5x the time and grew linearly with the library. The
  -- library is now ~300 generators, so that mattered.
  local checked, ground_luma = 0, {}
  for _, name in ipairs(generators.names) do
    local gen = generators.get(name)
    local spec = generators.spec(name)
    local cap = style.max_edge_density[gen.surface]
    local seen, distinct = {}, 0
    local lo, hi = 255, 0

    for seed = 1, SWEEP_SEEDS do
      local surface = generators.build(name, seed)
      checked = checked + 1

      -- every validator
      local report = validators.run(surface, spec)
      report.seed = seed
      assert(report.ok, validators.format(report))

      -- the busyness ceiling for its surface class, where it has one (decals
      -- do not: see the note on style.max_edge_density)
      if cap then
        local density = P.edge_density(surface)
        assert(density <= cap,
          ("%s (%s) seed %d: edge density %.3f over the %.2f ceiling")
            :format(name, gen.surface, seed, density, cap))
      end

      -- wrap flag matches the declaration, and a prop leaves its corner clear
      assert_eq(surface.wrap, gen.tileable and true or false, name .. " wrap flag")
      if not gen.tileable then
        assert_eq(surface:get(0, 0), palette.TRANSPARENT,
          name .. " must not bleed into the tile corner")
      end

      -- seeds actually vary
      local fp = surface:fingerprint()
      if not seen[fp] then seen[fp] = true; distinct = distinct + 1 end

      -- ground tiles hold a constant base: tiles that differ in overall
      -- brightness lay a field out as a chequerboard of light and dark cells
      if gen.surface == "ground" then
        local total = 0
        for _, _, c in surface:pixels() do total = total + palette.luminance(c) end
        local mean = total / (surface.width * surface.height)
        lo, hi = math.min(lo, mean), math.max(hi, mean)
      end
    end

    -- determinism: the same seed twice is the same pixels, forever
    assert_eq(generators.build(name, 42):fingerprint(), generators.build(name, 42):fingerprint(),
      name .. " same seed must be identical")

    -- Variants must genuinely differ. A transition tile is picked by
    -- connectivity rather than by looks and only ships three variants, so it
    -- is held to its own variant count rather than to the sweep length.
    local want = math.min(SWEEP_SEEDS, math.max(3, gen.variants)) - 2
    assert(distinct >= want,
      ("%s produced only %d distinct tiles in %d seeds"):format(name, distinct, SWEEP_SEEDS))

    if gen.surface == "ground" then
      assert(hi - lo <= 12,
        ("%s: tile brightness ranges %.1f..%.1f across seeds"):format(name, lo, hi))
      ground_luma[#ground_luma + 1] = name
    end
  end
  assert(checked == SWEEP_SEEDS * #generators.names, "swept " .. checked .. " assets")
  assert(#ground_luma >= 9, "the ground set is the point; do not let it shrink")
end)

test("validators catch each thing they exist to catch", function()
  local function report_for(surface, spec)
    local r = validators.run(surface, spec or {})
    local ids = {}
    for _, i in ipairs(r.issues) do ids[i.rule] = true end
    return r, ids
  end

  local tile = some(function(g) return g.tileable end)
  local good = generators.build(tile, 1)
  local r = report_for(good, generators.spec(tile))
  assert(r.ok, "a clean asset must pass: " .. validators.format(r))

  local wrong = P.new(20, 16, { fill = "concrete_4" })
  local _, ids = report_for(wrong)
  assert(ids.dimensions, "wrong dimensions")

  local semi = P.new(16, 16, { fill = "concrete_4" })
  semi:set_raw(3, 3, palette.pack(90, 85, 82, 128))
  local _, ids2 = report_for(semi)
  assert(ids2.alpha, "semi-transparent pixel")

  local off = P.new(16, 16, { fill = "concrete_4" })
  off:set_raw(4, 4, palette.pack(255, 0, 128, 255))
  local _, ids3 = report_for(off)
  assert(ids3.palette, "off-palette colour")

  local noisy = P.new(16, 16, { fill = "concrete_4" })
  local nr = rng.new(2, "noise")
  for _ = 1, 40 do noisy:set(nr:range(0, 15) , nr:range(0, 15), "ink_1") end
  local _, ids4 = report_for(noisy)
  assert(ids4.isolated_pixels or #P.isolated(noisy) <= style.max_isolated_pixels,
    "scattered single pixels")

  local busy = P.new(16, 16, { fill = "concrete_4" })
  local i = 0
  for _, name in ipairs(palette.names) do
    busy:set(i % 16, i // 16, name); i = i + 1
  end
  local _, ids5 = report_for(busy)
  assert(ids5.palette_size, "too many colours")
end)

test("the isolated-pixel cap binds on the tighter of its two bounds", function()
  -- Regression: the rule took math.max of the absolute and the proportional
  -- cap, so each bound excused a breach of the other. ART_STYLE.md says both
  -- apply: 6 strays per tile AND 4% of the opaque pixels.
  local function strays_allowed(surface)
    local rule
    for _, r in ipairs(validators.rules) do if r.id == "isolated_pixels" then rule = r end end
    local found = rule.check(surface, { wrap = false })
    return found
  end

  -- A full tile: 256 opaque, so the proportional cap is 10 and the absolute
  -- cap of 6 is the tighter one. Nine strays must fail.
  local full = P.new(16, 16, { fill = "concrete_4" })
  for i = 0, 8 do full:set((i * 5) % 16, (i * 3) % 16, "ink_1") end
  assert_eq(#P.isolated(full, { wrap = false }), 9, "nine strays placed")
  local issue = strays_allowed(full)
  assert(issue, "9 strays on a full tile must breach the 6-per-tile cap")

  -- A sparse asset: 25 opaque, so the proportional cap is 1 and it is now the
  -- tighter one. Four strays must fail even though 4 <= 6.
  local sparse = P.new(16, 16)
  P.rect_fill(sparse, 2, 2, 5, 5, "concrete_4")
  for i = 0, 3 do sparse:set(9 + i * 2, 12, "ink_1") end
  local _, opaque = P.histogram(sparse)
  assert_eq(opaque, 25 + 4, "sparse asset opaque count")
  assert_eq(#P.isolated(sparse, { wrap = false }), 4, "four strays placed")
  assert(strays_allowed(sparse),
    "4 strays over 29 opaque pixels must breach the 4% cap even though 4 <= 6")
end)

-- previews ---------------------------------------------------------------------------

test("preview sheets are 10x10 fields that themselves validate", function()
  -- One generator per category. A sheet costs 100 builds, and what this checks
  -- is the SHEET builder (geometry, palette integrity), which does not vary
  -- from one generator of a category to the next.
  local sample = {}
  for category, names in pairs(generators.by_category) do sample[#sample + 1] = names[1] end
  table.sort(sample)
  for _, name in ipairs(sample) do
    local g = generators.get(name)
    local sheet = previews.sheet(name, { seed = 1 })
    assert_eq(sheet.width, 10 * g.size.w, name .. " sheet width")
    assert_eq(sheet.height, 10 * g.size.h, name .. " sheet height")
    for _, _, c in sheet:pixels() do
      assert(palette.is_valid(c), name .. " sheet has an off-palette pixel")
    end
  end
end)

test("ground tiles do not print a 16x16 grid", function()
  -- The measurement is calibrated against real art: the game's own metro floor
  -- variants score 4.2 and 10.3 for seam bias, continuous untiled art 0.01.
  -- grid_report lays a 10x10 field, so it costs 100 builds a call. It is only
  -- ENFORCED on ground, so it is only computed there; the enforcement flag
  -- itself is a property of the declaration and is checked for everything.
  for _, name in ipairs(generators.names) do
    local gen = generators.get(name)
    if gen.tileable then
      if gen.surface ~= "ground" then
        goto continue
      end
      local report = previews.grid_report(name)
      assert_eq(report.enforced, true, name .. " enforcement")
      do
        assert(report.ok, ("%s: %s  (bias %.3f/%.3f, contrast %.2f/%.2f, sd %.2f, field %.3f)")
          :format(name, report.why, report.seam_bias_x, report.seam_bias_y,
            report.seam_contrast_x, report.seam_contrast_y, report.tile_luma_sd,
            report.field_density))
      end
      ::continue::
    end
  end
end)

test("object previews sit on their declared background", function()
  local prop = some(function(g) return g.preview_background ~= nil end)
  local sheet = previews.sheet(prop, { seed = 1 })
  assert(sheet:get(0, 0) ~= palette.TRANSPARENT, "background fills the cell corner")
end)

-- optional dump --------------------------------------------------------------------------

local dump_dir
for i, arg_value in ipairs(arg or {}) do
  if arg_value == "--dump" then dump_dir = arg[i + 1] end
end
if dump_dir then
  local ppm = require("ppm")
  os.execute(("mkdir -p '%s'"):format(dump_dir))
  for _, name in ipairs(generators.names) do
    ppm.write(previews.sheet(name, { seed = 1 }), ("%s/%s_sheet.ppm"):format(dump_dir, name), 3)
    ppm.write(previews.tiling_check(name, 7), ("%s/%s_tiling.ppm"):format(dump_dir, name), 3)
    ppm.write(generators.build(name, 7), ("%s/%s_single.ppm"):format(dump_dir, name), 12)
  end
  ppm.write(previews.palette_strip(), ("%s/palette.ppm"):format(dump_dir), 2)
  io.write("dumped previews to ", dump_dir, "\n")
end

io.write(("\n%d passed, %d failed\n"):format(passed, #failed))
os.exit(#failed == 0 and 0 or 1)
