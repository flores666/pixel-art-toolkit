-- generators/props.lua -- the gameplay prop library.
--
-- The objects a player walks up to, hides behind, loots or shoots. At 16px the
-- SILHOUETTE IS THE ASSET -- micro-detail is invisible at 1x and a prop that
-- cannot be told from another prop by its outline alone has failed however
-- nicely its surface is drawn. So every generator here starts from a distinct
-- overall shape, and only then fills it.
--
-- What varies with the seed is wear, never structure (ART_STYLE.md 11): a row
-- of the same locker has to read as a row of the same locker. The
-- variant_similarity validator enforces both ends of that -- variants must
-- share at least 55% of their pixels to still be the same object, and at most
-- 99.5% to be worth having.
--
-- `supply_crate` and `rusted_barrel` keep their own files: they shipped first,
-- levels already name them, and they are the reference for how a prop in this
-- world is lit.

local P = require("pixel_utils")
local palette = require("palette")
local materials = require("materials")
local object = require("object")

local metal, wood, concrete = materials.metal, materials.wood, materials.concrete

local set = {}
local function prop(spec)
  set[#set + 1] = {
    name = spec.name,
    title = spec.title,
    size = { w = spec.w or 16, h = spec.h or 16 },
    tileable = false,
    surface = spec.surface or "prop",
    category = "prop",
    collision = spec.collision or "hull",
    variants = spec.variants or 6,
    max_interior_holes = spec.max_interior_holes,
    preview_background = spec.background or "concrete_ground",
    build = function(rng_stream, opts)
      local s = P.new(spec.w or 16, spec.h or 16)
      spec.draw(s, rng_stream, opts or {})
      return object.finish(s, rng_stream, {
        outline = spec.outline, shadow = spec.shadow, wear = spec.wear,
      })
    end,
  }
end

local STEEL = { ramp = "metal",
  rust = { { value = 0.05, weight = 2 }, { value = 0.14, weight = 3 }, { value = 0.26, weight = 2 } },
  dirt = { { value = 0.05, weight = 2 }, { value = 0.12, weight = 2 } } }
local TIMBER = { ramp = "wood",
  rust = { { value = 0, weight = 3 }, { value = 0.08, weight = 2 } },
  dirt = { { value = 0.06, weight = 2 }, { value = 0.14, weight = 2 } } }

-- Containers ----------------------------------------------------------------

prop { name = "wooden_crate", title = "Wooden crate 16x16", variants = 8, wear = TIMBER,
  draw = function(s, r)
    -- Boards running the other way from supply_crate, and a corner batten, so
    -- the two crates are told apart by their construction and not only by
    -- their wear.
    local x0, y0, w, h = 2, 3, 12, 11
    P.rect_fill(s, x0, y0, w, h, "wood_4")
    wood.fill(s, r:branch("grain"), { area = { x = x0, y = y0, w = w, h = h }, axis = "v",
      base = "wood_4",
      mask = function(x, y) return x >= x0 and x < x0 + w and y >= y0 and y < y0 + h end })
    -- lid face into the light, foot in its own shadow
    P.rect_fill(s, x0, y0, w, 1, "wood_5")
    P.rect_fill(s, x0, y0 + h - 1, w, 1, "wood_2")
    -- vertical boards
    wood.planks(s, r:branch("boards"), { area = { x = x0, y = y0, w = w, h = h },
      axis = "v", pitch = 4 })
    -- the corner battens, which is what says "crate" rather than "box"
    P.vline(s, x0, y0, h, "wood_5")
    P.vline(s, x0 + w - 1, y0, h, "wood_3")
    if r:chance(0.5) then wood.knot(s, r:range(x0 + 2, x0 + w - 3), r:range(y0 + 3, y0 + h - 3), {}) end
  end }

prop { name = "metal_crate", title = "Metal crate 16x16", variants = 8, wear = STEEL,
  draw = function(s, r)
    -- A welded steel box: ribbed lid, a lip round the top, corner gussets. The
    -- rib pattern is what separates it from the wooden crates at 1x.
    local x0, y0, w, h = 2, 3, 12, 11
    object.box(s, x0, y0, w, h, "metal", 4)
    P.rect_fill(s, x0, y0, w, 2, "metal_5")
    P.rect_fill(s, x0 + 1, y0, w - 2, 1, "metal_6")
    -- ribs, as broken runs so they never become a comb
    local rib = r:branch("rib")
    for x = x0 + 2, x0 + w - 3, 3 do
      P.broken_run(s, "v", x, y0 + 3, y0 + h - 2, rib,
        { delta = -1, run = { 3, 6 }, gap = { 1, 2 } })
    end
    -- corner gussets and the two latches
    for _, cx in ipairs { x0, x0 + w - 2 } do
      P.rect_fill(s, cx, y0 + h - 3, 2, 2, "metal_3")
      P.pixel(s, cx, y0 + h - 3, "metal_5")
    end
    P.rect_fill(s, x0 + w // 2 - 1, y0 + 2, 2, 2, "metal_6")
  end }

prop { name = "supply_box", title = "Supply box 16x16", variants = 8, wear = STEEL,
  draw = function(s, r)
    -- Lower and wider than a crate, with a hinged lid standing proud: an
    -- ammunition-box silhouette, distinct at 1x because it is the only
    -- container in the kit that is wider than it is tall.
    local x0, y0, w, h = 1, 6, 14, 8
    object.box(s, x0, y0, w, h, "metal", 4)
    -- the lid, one pixel proud on each side
    P.rect_fill(s, x0 - 1 + 1, y0 - 2, w, 3, "metal_5")
    P.rect_fill(s, x0, y0 - 2, w, 1, "metal_6")
    P.rect_fill(s, x0, y0 + 1, w, 1, "metal_3")
    -- the carrying handle on the lid, and the catch on the front
    P.rect_fill(s, x0 + w // 2 - 2, y0 - 3, 4, 1, "metal_5")
    P.pixel(s, x0 + w // 2 - 2, y0 - 3, "metal_6")
    P.rect_fill(s, x0 + w // 2 - 1, y0 + 3, 2, 2, "metal_2")
    -- a stencil mark, faded: one pair of pixels is all that reads
    if r:chance(0.6) then P.rect_fill(s, x0 + 2, y0 + 4, 2, 1, "concrete_5") end
  end }

-- Furniture -----------------------------------------------------------------

prop { name = "locker", title = "Steel locker 16x32", w = 16, h = 32, variants = 8,
  wear = STEEL,
  draw = function(s, r)
    -- Tall and narrow, which is the whole silhouette. Two doors, a vent slot
    -- at the top of each and a handle -- and the doors are what fix the scale:
    -- without the division it reads as a cabinet twice the size.
    local x0, y0, w, h = 3, 4, 10, 26
    object.box(s, x0, y0, w, h, "metal", 4)
    P.rect_fill(s, x0, y0, w, 2, "metal_5")
    P.rect_fill(s, x0 + 1, y0, w - 2, 1, "metal_6")
    -- the door division and the door faces, inset so they read as doors
    P.vline(s, x0 + w // 2, y0 + 3, h - 5, "metal_2")
    for _, dx in ipairs { x0 + 1, x0 + w // 2 + 1 } do
      P.rect(s, dx, y0 + 3, w // 2 - 2, h - 6, "metal_3")
      -- vent slots: three short runs at the top of each door
      for i = 0, 2 do P.hline(s, dx + 1, y0 + 5 + i * 2, w // 2 - 4, "metal_2") end
      -- handle, low, on the outer edge of each door
      P.rect_fill(s, dx + 1, y0 + h - 12, 1, 3, "metal_6")
    end
    -- the plinth
    P.rect_fill(s, x0, y0 + h - 2, w, 2, "metal_2")
  end }

prop { name = "cabinet", title = "Cabinet 16x32", w = 16, h = 32, variants = 8,
  wear = TIMBER,
  draw = function(s, r)
    -- Timber office furniture: a carcass with three drawers. Horizontal
    -- divisions, where the locker's are vertical, so the two read differently
    -- from across a room.
    local x0, y0, w, h = 2, 8, 12, 22
    P.rect_fill(s, x0, y0, w, h, "wood_4")
    wood.fill(s, r:branch("grain"), { area = { x = x0, y = y0, w = w, h = h }, axis = "h",
      base = "wood_4",
      mask = function(x, y) return x >= x0 and x < x0 + w and y >= y0 and y < y0 + h end })
    P.rect_fill(s, x0, y0, w, 1, "wood_5")
    P.rect_fill(s, x0, y0, 1, h, "wood_5")
    P.rect_fill(s, x0 + w - 1, y0, 1, h, "wood_2")
    -- three drawers, each a recess: dark cut with the lit lip below it
    for i = 0, 2 do
      local dy = y0 + 2 + i * 6
      P.hline(s, x0 + 1, dy, w - 2, "wood_2")
      P.hline(s, x0 + 1, dy + 1, w - 2, "wood_5")
      -- the pull: a run, centred, two pixels
      P.rect_fill(s, x0 + w // 2 - 1, dy + 3, 2, 1, "wood_5")
    end
    P.rect_fill(s, x0, y0 + h - 1, w, 1, "wood_2")
  end }

prop { name = "cabinet_broken", title = "Cabinet, broken 16x32", w = 16, h = 32,
  variants = 8, max_interior_holes = 4, wear = TIMBER,
  draw = function(s, r)
    -- Doors off, one drawer hanging out, the carcass split. The HANGING DRAWER
    -- is the read: it breaks the rectangle, and a broken silhouette is what
    -- says "ransacked" from across the room.
    local x0, y0, w, h = 2, 8, 12, 22
    P.rect_fill(s, x0, y0, w, h, "wood_3")
    P.rect_fill(s, x0, y0, w, 1, "wood_4")
    P.rect_fill(s, x0, y0, 1, h, "wood_4")
    P.rect_fill(s, x0 + w - 1, y0, 1, h, "wood_2")
    -- the empty drawer voids: darkness, because there is nothing behind them
    for i = 0, 2 do
      local dy = y0 + 2 + i * 6
      if i ~= 1 then
        P.rect_fill(s, x0 + 1, dy, w - 2, 4, "ink_4")
        P.hline(s, x0 + 1, dy, w - 2, "wood_2")
        P.hline(s, x0 + 1, dy + 4, w - 2, "wood_4")   -- lit lower lip of the recess
      end
    end
    -- the drawer that is hanging out, tilted, sticking past the carcass
    local dy = y0 + 8
    local out = r:range(2, 4)
    P.rect_fill(s, x0 + 1 - out, dy, w - 2 + out, 4, "wood_4")
    P.rect_fill(s, x0 + 1 - out, dy, w - 2 + out, 1, "wood_5")
    P.rect_fill(s, x0 + 1 - out, dy + 3, w - 2 + out, 1, "wood_2")
    P.rect_fill(s, x0 + 1 - out, dy, 1, 4, "wood_5")
    -- a split in the carcass side
    if r:chance(0.7) then
      materials.concrete.crack(s, x0 + w - 2, r:range(y0 + 12, y0 + h - 3),
        r:range(4, 7), r, { color = "wood_2", branches = 0 })
    end
    P.rect_fill(s, x0, y0 + h - 1, w, 1, "wood_2")
  end }

prop { name = "bench", title = "Bench 32x16", w = 32, h = 16, variants = 8,
  collision = "low", wear = TIMBER, max_interior_holes = 4,
  draw = function(s, r)
    -- Slatted seat on steel legs, seen from slightly above. The GAP under the
    -- seat is the silhouette cue -- without it a bench is a plank on the floor.
    local y = 7
    -- the seat: three slats with dark gaps
    for i = 0, 2 do
      local sy = y + i * 2
      P.rect_fill(s, 1, sy, 30, 2, "wood_4")
      P.rect_fill(s, 1, sy, 30, 1, "wood_5")
      P.hline(s, 1, sy + 1, 30, "wood_2")
    end
    -- the legs, showing under the seat
    for _, lx in ipairs { 3, 27 } do
      object.upright(s, lx, y + 6, 14, "metal", 4, { width = 2 })
      -- the foot spreads, which is what stops a leg reading as a pin
      P.rect_fill(s, lx - 1, 13, 4, 1, "metal_3")
    end
    -- a missing slat end, because nothing here is maintained
    if r:chance(0.5) then
      local mx = r:chance(0.5) and 1 or 27
      P.rect_fill(s, mx, y + 4, 4, 2, palette.TRANSPARENT)
    end
  end }

prop { name = "chair", title = "Chair 16x16", variants = 8, collision = "low",
  wear = TIMBER, max_interior_holes = 3,
  draw = function(s, r)
    -- Back, seat, four legs -- and the back is what makes it a chair rather
    -- than a stool, so it gets real height. Tipped over on some variants,
    -- because an upright chair in this world is the surprising case.
    local tipped = r:chance(0.35)
    if not tipped then
      P.rect_fill(s, 4, 3, 8, 6, "wood_4")            -- back
      P.rect_fill(s, 4, 3, 8, 1, "wood_5")
      P.rect_fill(s, 5, 5, 6, 2, "ink_4")             -- the gap in the back
      P.rect_fill(s, 3, 9, 10, 2, "wood_4")           -- seat
      P.rect_fill(s, 3, 9, 10, 1, "wood_5")
      for _, lx in ipairs { 4, 11 } do
        object.upright(s, lx, 11, 14, "wood", 3, { width = 1 })
      end
    else
      -- On its side: the back becomes a horizontal slab and the legs stick
      -- out sideways. Same parts, rotated -- the lighting stays upper-left.
      P.rect_fill(s, 3, 8, 6, 5, "wood_4")
      P.rect_fill(s, 3, 8, 6, 1, "wood_5")
      P.rect_fill(s, 9, 9, 4, 3, "wood_3")
      for _, ly in ipairs { 9, 12 } do
        for k = 0, 2 do P.pixel(s, 13 + k, ly, "wood_3") end
        P.pixel(s, 13, ly - 1, "wood_4")
      end
    end
  end }

prop { name = "small_table", title = "Small table 16x16", variants = 6,
  collision = "low", wear = TIMBER, max_interior_holes = 3,
  draw = function(s, r)
    -- A flat top with legs under it. The top is the widest thing in the cell
    -- and the legs are inset, which is the silhouette that says "table".
    P.rect_fill(s, 1, 6, 14, 3, "wood_4")
    P.rect_fill(s, 1, 6, 14, 1, "wood_5")
    P.rect_fill(s, 1, 8, 14, 1, "wood_2")
    wood.fill(s, r:branch("grain"), { area = { x = 1, y = 6, w = 14, h = 2 }, axis = "h",
      base = "wood_4", mask = function(x, y) return y >= 6 and y <= 7 end })
    for _, lx in ipairs { 3, 11 } do
      object.upright(s, lx, 9, 14, "wood", 3, { width = 2 })
    end
  end }

prop { name = "utility_machine", title = "Utility machine 16x32", w = 16, h = 32,
  variants = 8, wear = STEEL,
  draw = function(s, r)
    -- A vending or dispensing machine: a tall cabinet with a big dark front
    -- panel where the glass was, a control strip and a delivery slot. The dark
    -- panel is the read -- it is the only large near-black area on any prop in
    -- the kit, so it identifies the object instantly.
    local x0, y0, w, h = 2, 3, 12, 27
    object.box(s, x0, y0, w, h, "metal", 4)
    P.rect_fill(s, x0, y0, w, 2, "metal_5")
    P.rect_fill(s, x0 + 1, y0, w - 2, 1, "metal_6")
    -- the broken window: darkness, with the remaining glazing lit on the rim
    P.rect_fill(s, x0 + 1, y0 + 3, w - 4, 14, "ink_4")
    P.rect(s, x0 + 1, y0 + 3, w - 4, 14, "metal_2")
    P.hline(s, x0 + 1, y0 + 3, w - 4, "metal_5")
    -- a few shards still in the frame
    if r:chance(0.7) then
      for i = 0, r:range(1, 3) do
        P.pixel(s, x0 + 2 + i * 2, y0 + 4, "concrete_6")
        P.pixel(s, x0 + 2 + i * 2, y0 + 5, "concrete_5")
      end
    end
    -- the control strip down the right, and the delivery slot at the bottom
    P.rect_fill(s, x0 + w - 3, y0 + 4, 2, 10, "metal_3")
    for i = 0, 3 do P.pixel(s, x0 + w - 3, y0 + 5 + i * 2, "metal_5") end
    P.rect_fill(s, x0 + 2, y0 + 19, w - 5, 3, "ink_4")
    P.hline(s, x0 + 2, y0 + 19, w - 5, "metal_5")
    P.rect_fill(s, x0, y0 + h - 2, w, 2, "metal_2")
  end }

-- Refuse --------------------------------------------------------------------

prop { name = "trash_bin", title = "Trash bin 16x16", variants = 8, wear = STEEL,
  max_interior_holes = 3,
  draw = function(s, r)
    -- A cylindrical bin with an open MOUTH -- the one legitimately enclosed
    -- hole in the prop kit, and the reason max_interior_holes exists as a
    -- budget rather than a ban.
    local x0, x1, y0, y1 = 3, 12, 4, 14
    object.cylinder(s, x0, y0, x1 - x0 + 1, y1 - y0 + 1, "metal", 4)
    -- the rim, proud of the body, and the dark inside
    P.rect_fill(s, x0 - 1, y0, x1 - x0 + 3, 2, "metal_5")
    P.rect_fill(s, x0 - 1, y0, x1 - x0 + 3, 1, "metal_6")
    P.rect_fill(s, x0 + 1, y0 + 1, x1 - x0 - 1, 2, "ink_4")
    -- two bands round the body, lit on top with their own shadow under
    for _, by in ipairs { y0 + 4, y0 + 8 } do
      P.rect_fill_shift(s, x0, by, x1 - x0 + 1, 1, 1)
      P.rect_fill_shift(s, x0, by + 1, x1 - x0 + 1, 1, -1)
    end
    -- rubbish coming out of the top, on most variants
    if r:chance(0.7) then
      local t = r:branch("spill")
      for _ = 1, t:range(1, 2) do
        local tx = t:range(x0 + 1, x1 - 2)
        P.rect_fill(s, tx, y0 - 1, 2, 2, t:chance(0.5) and "concrete_5" or "straw_3")
        P.pixel(s, tx, y0 - 1, "concrete_6")
      end
    end
  end }

prop { name = "trash_pile", title = "Garbage bags / trash pile 16x16", variants = 10,
  collision = "low",
  draw = function(s, r)
    -- Bags. A bag is a ROUNDED lump with a lit crown and a pinched neck, and
    -- two or three of them slumped together is the asset -- which makes this
    -- the one pile in the library that is legitimately several masses rather
    -- than one, because bags do not fuse.
    -- Bigger, and NOT near-black. At radius 3 in ink_4 the bags read as three
    -- small dark smudges rather than as sacks: near-black reserves no room for
    -- the lit crown that gives a bag its form, and the asset needs to be
    -- legible at 1x against dark tarmac as well as against pale concrete.
    for i = 1, r:range(2, 3) do
      local bx = 4 + (i - 1) * r:range(4, 5)
      local by = r:range(10, 12)
      local rad = r:range(4, 5)
      local body = palette.resolve(r:chance(0.6) and "metal_3" or "metal_4")
      P.cluster(s, bx, by, rad * rad, body, r, { spread = 0.2 })
      -- the crown, catching the light, and the pinched neck above it
      P.pixel(s, bx - 1, by - rad + 1, palette.shift(body, 2))
      P.pixel(s, bx, by - rad + 1, palette.shift(body, 1))
      P.pixel(s, bx, by - rad, palette.shift(body, 1))
    end
    -- and what has spilled out
    materials.debris.fill(s, r:branch("spill"), { coverage = 0.10,
      area = { x = 1, y = 12, w = 14, h = 3 },
      kinds = { { value = "straw_3", weight = 2 }, { value = "concrete_5", weight = 2 },
                { value = "wood_3", weight = 1 } } })
  end }

-- Barricades ----------------------------------------------------------------

prop { name = "barricade", title = "Barricade 32x16", w = 32, h = 16, variants = 8,
  collision = "low", wear = STEEL, max_interior_holes = 4,
  draw = function(s, r)
    -- A manufactured barrier: two horizontal rails on splayed legs, with the
    -- gap between the rails showing through. Regular, because someone made it.
    for i = 0, 1 do
      local y = 5 + i * 4
      object.rail(s, 1, 30, y, "metal", 4, { thickness = 2 })
      -- the hazard banding, as alternating runs -- the palette has no white,
      -- so this is concrete_5 against metal_4 and it still reads
      local band = r:branch("band" .. i)
      P.broken_run(s, "h", y, 2, 29, band,
        { color = palette.by_name.concrete_5, run = { 3, 4 }, gap = { 3, 4 } })
    end
    for _, lx in ipairs { 3, 26 } do
      object.upright(s, lx, 9, 14, "metal", 4, { width = 2 })
      P.rect_fill(s, lx - 1, 13, 5, 1, "metal_3")
      -- the diagonal brace to the rail
      P.line(s, lx + 1, 13, lx + 3, 9, "metal_3")
    end
  end }

prop { name = "improvised_barricade", title = "Improvised barricade 32x16",
  w = 32, h = 16, variants = 10, collision = "low", max_interior_holes = 4,
  draw = function(s, r)
    -- Made of whatever was to hand: pallets, sheet, a length of pipe, timber
    -- across the top. IRREGULAR is the entire point, and it is what
    -- distinguishes it from the manufactured barricade at a glance -- so the
    -- members are at differing heights and angles and the materials are mixed.
    -- One connected mass, though: a barricade with gaps in the middle is a
    -- pile of parts.
    local ground = 14
    -- The MEMBER LAYOUT IS FIXED, and only what each member is made of and how
    -- tall it stands varies with the seed. Re-rolling the count, the spacing
    -- and the widths per seed made every variant a different object -- the
    -- variant_similarity floor caught it at 44% shared pixels against a 55%
    -- floor for a prop, and it was right: ART_STYLE.md 11 says silhouette and
    -- structure hold still or a row of the same prop stops reading as one.
    --
    -- "Improvised" is a fixed characteristic of this barricade, not something
    -- to re-roll: the irregular spacing below is deliberate and constant, and
    -- the seed changes the materials and the wear.
    local MEMBERS = { { x = 1, w = 6 }, { x = 8, w = 5 }, { x = 14, w = 7 },
                      { x = 22, w = 5 }, { x = 27, w = 4 } }
    for _, m in ipairs(MEMBERS) do
      local x, wid = m.x, m.w
      local top = r:range(5, 7)
      local mat = r:weighted {
        { value = "wood_4", weight = 3 }, { value = "metal_4", weight = 2 },
        { value = "concrete_4", weight = 1 } }
      P.rect_fill(s, x, top, math.min(wid, 31 - x), ground - top, mat)
      P.rect_fill(s, x, top, math.min(wid, 31 - x), 1, palette.shift(palette.resolve(mat), 1))
      P.vline(s, math.min(30, x + wid - 1), top, ground - top, palette.shift(palette.resolve(mat), -1))
    end
    -- a length of pipe or timber laid across the top, tying it together
    local ty = r:range(3, 4)
    for x = 1, 30 do
      P.pixel(s, x, ty, "metal_4")
      P.pixel(s, x, ty + 1, "metal_3")
    end
    P.broken_run(s, "h", ty, 1, 30, r:branch("lit"), { delta = 1, run = { 4, 8 }, gap = { 2, 4 } })
    -- and the base, so the whole thing sits on the ground rather than floating
    P.rect_fill(s, 1, ground, 30, 1, "metal_2")
  end,
  wear = { ramp = "metal",
    rust = { { value = 0.10, weight = 2 }, { value = 0.20, weight = 2 } } } }

prop { name = "sandbag_barrier", title = "Sandbag barrier 32x16", w = 32, h = 16,
  variants = 8, collision = "low",
  draw = function(s, r)
    -- Courses of filled bags, each bag a rounded lump with a lit crown, laid
    -- in overlapping rows. It fits the art direction because the bags are
    -- hessian -- straw and earth colours, nothing military-green -- and
    -- because the palette's warm ramp is exactly right for wet sacking.
    -- A BAG IS NOT A BRICK, and the first version was: square ends, uniform
    -- length, courses offset by a constant. Laid up like that it read as
    -- coursed masonry, which is the one thing this asset must not look like.
    -- Three changes fix it -- the ends are rounded off, the lengths vary, and
    -- each course starts at its own offset -- because what identifies filled
    -- sacking at this size is that no two units are the same shape.
    for course = 0, 2 do
      local y = 12 - course * 3
      local offset = r:range(0, 4)
      local x = 1 + offset
      while x < 29 do
        local bw = r:range(4, 6)
        if x + bw > 30 then break end
        local body = palette.resolve(r:chance(0.55) and "straw_2" or "earth_3")
        -- a bag: wider than tall, ends rounded, slumped onto the one below
        P.rect_fill(s, x, y, bw, 3, body)
        P.pixel(s, x, y, palette.TRANSPARENT)               -- round the corners off
        P.pixel(s, x + bw - 1, y, palette.TRANSPARENT)
        P.rect_fill(s, x + 1, y, bw - 2, 1, palette.shift(body, 1))
        P.rect_fill(s, x, y + 2, bw, 1, palette.shift(body, -1))
        -- The bag's left and right edges take and lose the light. Drawn on the
        -- MIDDLE row only: applying them down the full height of a 3px bag
        -- outlined every bag in two extra values and left the busiest seed at
        -- 0.656 against the 0.65 ceiling. One pixel each is enough to round
        -- the form at this size.
        P.pixel(s, x, y + 1, palette.shift(body, 1))
        -- No per-bag seam. It was one pixel in the middle of a five-pixel bag
        -- and with eighteen bags on the asset it pushed the busiest seed to
        -- 0.657 against the 0.65 prop ceiling -- for a detail that is
        -- invisible at 1x. The crown and the shaded lower edge already say
        -- "filled sack"; the seam only said "noise".
        x = x + bw + r:range(0, 1)
      end
    end
  end,
  wear = { ramp = "straw",
    dirt = { { value = 0.06, weight = 2 }, { value = 0.16, weight = 2 } },
    vegetation = { { value = 0, weight = 3 }, { value = 1, weight = 1 } },
    vegetation_area = { x = 2, y = 12, w = 28, h = 3 } } }

return set
